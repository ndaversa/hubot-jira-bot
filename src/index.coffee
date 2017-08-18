# Description:
# Lets you search for JIRA tickets, open
# them, transition them thru different states, comment on them, rank
# them up or down, start or stop watching them or change who is
# assigned to a ticket. Also, notifications for mentions, assignments and watched tickets.
#
# Dependencies:
# - moment
# - octokat
# - node-fetch
# - underscore
# - fuse.js
#
# Author:
#   ndaversa
#
# Contributions:
#   sjakubowski

_ = require "underscore"
moment = require "moment"

Config = require "./config"
Github = require "./github"
Help = require "./help"
Jira = require "./jira"
Adapters = require "./adapters"
Utils = require "./utils"

class JiraBot

  constructor: (@robot) ->
    return new JiraBot @robot unless @ instanceof JiraBot
    Utils.robot = @robot
    Utils.JiraBot = @

    @webhook = new Jira.Webhook @robot
    switch @robot.adapterName
      when "slack"
        @adapter = new Adapters.Slack @robot
      else
        @adapter = new Adapters.Generic @robot

    @registerWebhookListeners()
    @registerEventListeners()
    @registerRobotResponses()

  send: (context, message, filter=yes) ->
    context = @adapter.normalizeContext context
    message = @filterAttachmentsForPreviousMentions context, message if filter
    @adapter.send context, message

  filterAttachmentsForPreviousMentions: (context, message) ->
    return message if _(message).isString()
    return message unless message.attachments?.length > 0
    room = context.message.room

    removals = []
    for attachment in message.attachments when attachment and attachment.type is "JiraTicketAttachment"
      ticket = attachment.author_name?.trim().toUpperCase()
      continue unless Config.ticket.regex.test ticket

      key = "#{room}:#{ticket}"
      if Utils.cache.get key
        removals.push attachment
        Utils.Stats.increment "jirabot.surpress.attachment"
        @robot.logger.debug "Supressing ticket attachment for #{ticket} in #{@adapter.getRoomName context}"
      else
        Utils.cache.put key, true, Config.cache.mention.expiry

    message.attachments = _(message.attachments).difference removals
    return message

  matchJiraTicket: (context) ->
    if context.match?
      matches = context.match Config.ticket.regexGlobal
      unless matches and matches[0]
        urlMatch = context.match Config.jira.urlRegex
        if urlMatch and urlMatch[1]
          matches = [ urlMatch[1] ]

    if matches and matches[0]
      return matches
    else if context.message?.attachments?
      attachments = context.message.attachments
      for attachment in attachments when attachment.text?
        matches = attachment.text.match Config.ticket.regexGlobal
        if matches and matches[0]
          return matches
    return false

  prepareResponseForJiraTickets: (context) ->
    Promise.all(context.match.map (key) =>
      _attachments = []
      Jira.Create.fromKey(key).then (ticket) ->
        _attachments.push ticket.toAttachment()
        ticket
      .then (ticket) ->
        Github.PullRequests.fromKey ticket.key unless Config.github.disabled
      .then (prs) ->
        prs?.toAttachment()
      .then (attachments) ->
        _attachments.push a for a in attachments if attachments
        _attachments
    ).then (attachments) =>
      @send context, attachments: _(attachments).flatten()
    .catch (error) =>
      @send context, "#{error}"
      @robot.logger.error error.stack

  registerWebhookListeners: ->
    # Watchers
    disableDisclaimer = """
      If you wish to stop receiving notifications for the tickets you are watching, reply with:
      > jira disable notifications
    """
    @robot.on "JiraWebhookTicketInProgress", (ticket, event) =>
      assignee = Utils.lookupUserWithJira ticket.fields.assignee
      assigneeText = "."
      assigneeText = " by #{assignee}" if assignee isnt "Unassigned"

      @adapter.dm Utils.lookupChatUsersWithJira(ticket.watchers),
        text: """
          A ticket you are watching is now being worked on#{assigneeText}
        """
        author: event.user
        footer: disableDisclaimer
        attachments: [ ticket.toAttachment no ]
      Utils.Stats.increment "jirabot.webhook.ticket.inprogress"

    @robot.on "JiraWebhookTicketInReview", (ticket, event) =>
      assignee = Utils.lookupUserWithJira ticket.fields.assignee
      assigneeText = ""
      assigneeText = "Please message #{assignee} if you wish to provide feedback." if assignee isnt "Unassigned"

      @adapter.dm Utils.lookupChatUsersWithJira(ticket.watchers),
        text: """
          A ticket you are watching is now ready for review.
          #{assigneeText}
        """
        author: event.user
        footer: disableDisclaimer
        attachments: [ ticket.toAttachment no ]
      Utils.Stats.increment "jirabot.webhook.ticket.inreview"

    @robot.on "JiraWebhookTicketDone", (ticket, event) =>
      @adapter.dm Utils.lookupChatUsersWithJira(ticket.watchers),
        text: """
          A ticket you are watching has been marked `Done`.
        """
        author: event.user
        footer: disableDisclaimer
        attachments: [ ticket.toAttachment no ]
      Utils.Stats.increment "jirabot.webhook.ticket.done"

    # Comment notifications for watchers
    @robot.on "JiraWebhookTicketComment", (ticket, comment) =>
      watchers = (watcher for watcher in ticket.watchers when watcher.name isnt comment.author.name)
      @adapter.dm Utils.lookupChatUsersWithJira(watchers),
        text: """
          A ticket you are watching has a new comment from #{comment.author.displayName}:
          ```
          #{comment.body}
          ```
        """
        author: comment.author
        footer: disableDisclaimer
        attachments: [ ticket.toAttachment no ]
      Utils.Stats.increment "jirabot.webhook.ticket.comment"

    # Comment notifications for assignee
    @robot.on "JiraWebhookTicketComment", (ticket, comment) =>
      return unless ticket.fields.assignee
      return if ticket.watchers.length > 0 and _(ticket.watchers).findWhere name: ticket.fields.assignee.name
      return if ticket.fields.assignee.name is comment.author.name

      @adapter.dm Utils.lookupChatUsersWithJira(ticket.fields.assignee),
        text: """
          A ticket you are assigned to has a new comment from #{comment.author.displayName}:
          ```
          #{comment.body}
          ```
        """
        author: comment.author
        footer: disableDisclaimer
        attachments: [ ticket.toAttachment no ]
      Utils.Stats.increment "jirabot.webhook.ticket.comment"

    # Mentions
    @robot.on "JiraWebhookTicketMention", (ticket, user, event, context) =>
      @adapter.dm user,
        text: """
          You were mentioned in a ticket by #{event.user.displayName}:
          ```
          #{context}
          ```
        """
        author: event.user
        footer: disableDisclaimer
        attachments: [ ticket.toAttachment no ]
      Utils.Stats.increment "jirabot.webhook.ticket.mention"

    # Assigned
    @robot.on "JiraWebhookTicketAssigned", (ticket, user, event) =>
      @adapter.dm user,
        text: """
          You were assigned to a ticket by #{event.user.displayName}:
        """
        author: event.user
        footer: disableDisclaimer
        attachments: [ ticket.toAttachment no ]
      Utils.Stats.increment "jirabot.webhook.ticket.assigned"

  registerEventListeners: ->

    #Find Matches (for cross-script usage)
    @robot.on "JiraFindTicketMatches", (context, cb) =>
      cb @matchJiraTicket context

    #Prepare Responses For Tickets (for cross-script usage)
    @robot.on "JiraPrepareResponseForTickets", (context) =>
      @prepareResponseForJiraTickets context

    #Create
    @robot.on "JiraTicketCreated", (context, details) =>
      @send context,
        text: "Ticket created"
        attachments: [
          details.ticket.toAttachment no
          details.assignee
          details.transition
        ]
      Utils.Stats.increment "jirabot.ticket.create.success"

    @robot.on "JiraTicketCreationFailed", (error, context) =>
      robot.logger.error error.stack
      @send context, "Unable to create ticket #{error}"
      Utils.Stats.increment "jirabot.ticket.create.failed"

    #Created in another room
    @robot.on "JiraTicketCreatedElsewhere", (context, details) =>
      room = @adapter.getRoom context
      for r in Utils.lookupRoomsForProject details.ticket.fields.project.key
        @send r,
          text: "Ticket created in <##{room.id}|#{room.name}> by <@#{context.message.user.id}>"
          attachments: [
            details.ticket.toAttachment no
            details.assignee
            details.transition
          ]
      Utils.Stats.increment "jirabot.ticket.create.elsewhere"

    #Clone
    @robot.on "JiraTicketCloned", (ticket, channel, clone, context) =>
      room = @adapter.getRoom context
      @send channel,
        text: "Ticket created: Cloned from #{clone} in <##{room.id}|#{room.name}> by <@#{context.message.user.id}>"
        attachments: [ ticket.toAttachment no ]
      Utils.Stats.increment "jirabot.ticket.clone.success"

    @robot.on "JiraTicketCloneFailed", (error, ticket, context) =>
      @robot.logger.error error.stack
      room = @adapter.getRoom context
      @send context, "Unable to clone `#{ticket}` to the <\##{room.id}|#{room.name}> project :sadpanda:\n```#{error}```"
      Utils.Stats.increment "jirabot.ticket.clone.failed"

    #Transition
    @robot.on "JiraTicketTransitioned", (ticket, transition, context, includeAttachment=no) =>
      @send context,
        text: "Transitioned #{ticket.key} to `#{transition.to.name}`"
        attachments: [ ticket.toAttachment no ] if includeAttachment
      Utils.Stats.increment "jirabot.ticket.transition.success"

    @robot.on "JiraTicketTransitionFailed", (error, context) =>
      @robot.logger.error error.stack
      @send context, "#{error}"
      Utils.Stats.increment "jirabot.ticket.transition.failed"

    #Assign
    @robot.on "JiraTicketAssigned", (ticket, user, context, includeAttachment=no) =>
      @send context,
        text: "Assigned <@#{user.id}> to #{ticket.key}"
        attachments: [ ticket.toAttachment no ] if includeAttachment
      Utils.Stats.increment "jirabot.ticket.assign.success"

    @robot.on "JiraTicketUnassigned", (ticket, context, includeAttachment=no) =>
      @send context,
        text: "#{ticket.key} is now unassigned"
        attachments: [ ticket.toAttachment no ] if includeAttachment
      Utils.Stats.increment "jirabot.ticket.unassign.success"

    @robot.on "JiraTicketAssignmentFailed", (error, context) =>
      @robot.logger.error error.stack
      @send context, "#{error}"
      Utils.Stats.increment "jirabot.ticket.assign.failed"

    #Watch
    @robot.on "JiraTicketWatched", (ticket, user, context, includeAttachment=no) =>
      @send context,
        text: "Added <@#{user.id}> as a watcher on #{ticket.key}"
        attachments: [ ticket.toAttachment no ] if includeAttachment
      Utils.Stats.increment "jirabot.ticket.watch.success"

    @robot.on "JiraTicketUnwatched", (ticket, user, context, includeAttachment=no) =>
      @send context,
        text: "Removed <@#{user.id}> as a watcher on #{ticket.key}"
        attachments: [ ticket.toAttachment no ] if includeAttachment
      Utils.Stats.increment "jirabot.ticket.unwatch.success"

    @robot.on "JiraTicketWatchFailed", (error, context) =>
      @robot.logger.error error.stack
      @send context, "#{error}"
      Utils.Stats.increment "jirabot.ticket.watch.failed"

    #Rank
    @robot.on "JiraTicketRanked", (ticket, direction, context, includeAttachment=no) =>
      @send context,
        text: "Ranked #{ticket.key} to `#{direction}`"
        attachments: [ ticket.toAttachment no ] if includeAttachment
      Utils.Stats.increment "jirabot.ticket.rank.success"

    @robot.on "JiraTicketRankFailed", (error, context) =>
      @robot.logger.error error.stack
      @send context, "#{error}"
      Utils.Stats.increment "jirabot.ticket.rank.failed"

    #Labels
    @robot.on "JiraTicketLabelled", (ticket, context, includeAttachment=no) =>
      @send context,
        text: "Added labels to #{ticket.key}"
        attachments: [ ticket.toAttachment no ] if includeAttachment
      Utils.Stats.increment "jirabot.ticket.label.success"

    @robot.on "JiraTicketLabelFailed", (error, context) =>
      @robot.logger.error error.stack
      @send context, "#{error}"
      Utils.Stats.increment "jirabot.ticket.label.failed"

    #Comments
    @robot.on "JiraTicketCommented", (ticket, context, includeAttachment=no) =>
      @send context,
        text: "Added comment to #{ticket.key}"
        attachments: [ ticket.toAttachment no ] if includeAttachment
      Utils.Stats.increment "jirabot.ticket.comment.success"

    @robot.on "JiraTicketCommentFailed", (error, context) =>
      @robot.logger.error error.stack
      @send context, "#{error}"
      Utils.Stats.increment "jirabot.ticket.comment.failed"

  registerRobotResponses: ->
    #Help
    @robot.respond Config.help.regex, (context) =>
      context.finish()
      [ __, topic] = context.match
      @send context, Help.forTopic topic, @robot
      Utils.Stats.increment "command.jirabot.help"

    #Enable/Disable Watch Notifications
    @robot.respond Config.watch.notificationsRegex, (context) =>
      context.finish()
      [ __, state ] = context.match
      switch state
        when "allow", "start", "enable"
          @adapter.enableNotificationsFor context.message.user
          @send context, """
          JIRA Watch notifications have been *enabled*

          You will start receiving notifications for JIRA tickets you are watching

          If you wish to _disable_ them just send me this message:
          > jira disable notifications
          """
        when "disallow", "stop", "disable"
          @adapter.disableNotificationsFor context.message.user
          @send context, """
          JIRA Watch notifications have been *disabled*

          You will no longer receive notifications for JIRA tickets you are watching

          If you wish to _enable_ them again just send me this message:
          > jira enable notifications
          """
      Utils.Stats.increment "command.jirabot.toggleNotifications"

    #Search
    @robot.respond Config.search.regex, (context) =>
      context.finish()
      [__, query] = context.match
      room = context.message.room
      project = Config.maps.projects[room]
      Jira.Search.withQueryForProject(query, project, context)
      .then (results) =>
        attachments = (ticket.toAttachment() for ticket in results.tickets)
        @send context,
          text: results.text
          attachments: attachments
        , no
      .catch (error) =>
        @send context, "Unable to search for `#{query}` :sadpanda:"
        @robot.logger.error error.stack
      Utils.Stats.increment "command.jirabot.search"

    #Transition
    if Config.maps.transitions
      @robot.hear Config.transitions.regex, (context) =>
        context.finish()
        [ __, key, toState ] = context.match
        Jira.Transition.forTicketKeyToState key, toState, context, no
        Utils.Stats.increment "command.jirabot.transition"

    #Clone
    @robot.hear Config.clone.regex, (context) =>
      context.finish()
      [ __, ticket, channel ] = context.match
      project = Config.maps.projects[channel]
      Jira.Clone.fromTicketKeyToProject ticket, project, channel, context
      Utils.Stats.increment "command.jirabot.clone"

    #Watch
    @robot.hear Config.watch.regex, (context) =>
      context.finish()
      [ __, key, remove, person ] = context.match

      if remove
        Jira.Watch.forTicketKeyRemovePerson key, person, context, no
      else
        Jira.Watch.forTicketKeyForPerson key, person, context, no
      Utils.Stats.increment "command.jirabot.watch"

    #Rank
    @robot.hear Config.rank.regex, (context) =>
      context.finish()
      [ __, key, direction ] = context.match
      Jira.Rank.forTicketKeyByDirection key, direction, context, no
      Utils.Stats.increment "command.jirabot.rank"

    #Labels
    @robot.hear Config.labels.addRegex, (context) =>
      context.finish()
      [ __, key ] = context.match
      {input: input} = context.match
      labels = []
      labels = (input.match(Config.labels.regex).map((label) -> label.replace('#', '').trim())).concat(labels)

      Jira.Labels.forTicketKeyWith key, labels, context, no
      Utils.Stats.increment "command.jirabot.label"

    #Comment
    @robot.hear Config.comment.regex, (context) =>
      context.finish()
      [ __, key, comment ] = context.match

      Jira.Comment.forTicketKeyWith key, comment, context, no
      Utils.Stats.increment "command.jirabot.comment"

    #Subtask
    @robot.respond Config.subtask.regex, (context) =>
      context.finish()
      [ __, key, summary ] = context.match
      Jira.Create.subtaskFromKeyWith key, summary, context
      Utils.Stats.increment "command.jirabot.subtask"

    #Assign
    @robot.hear Config.assign.regex, (context) =>
      context.finish()
      [ __, key, remove, person ] = context.match

      if remove
        Jira.Assign.forTicketKeyToUnassigned key, context, no
      else
        Jira.Assign.forTicketKeyToPerson key, person, context, no

      Utils.Stats.increment "command.jirabot.assign"

    #Create
    @robot.respond Config.commands.regex, (context) =>
      [ __, project, command, summary ] = context.match
      room = project or @adapter.getRoomName context
      project = Config.maps.projects[room.toLowerCase()]
      type = Config.maps.types[command.toLowerCase()]

      unless project
        channels = []
        for team, key of Config.maps.projects
          room = @adapter.getRoom team
          channels.push " <\##{room.id}|#{room.name}>" if room
        return context.reply "#{type} must be submitted in one of the following project channels: #{channels}"

      if Config.duplicates.detection and @adapter.detectForDuplicates?
        @adapter.detectForDuplicates project, type, summary, context
      else
        Jira.Create.with project, type, summary, context

      Utils.Stats.increment "command.jirabot.create"

    #Mention ticket by url or key
    @robot.listen @matchJiraTicket, (context) =>
      @prepareResponseForJiraTickets context
      Utils.Stats.increment "command.jirabot.mention.ticket"

module.exports = JiraBot
