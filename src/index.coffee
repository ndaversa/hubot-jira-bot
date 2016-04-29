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
# Configuration:
#   HUBOT_JIRA_URL (format: "https://jira-domain.com:9090")
#   HUBOT_JIRA_USERNAME
#   HUBOT_JIRA_PASSWORD
#   HUBOT_JIRA_TYPES_MAP  {"story":"Story / Feature","bug":"Bug","task":"Task"}
#   HUBOT_JIRA_PROJECTS_MAP  {"web":"WEB","android":"AN","ios":"IOS","platform":"PLAT"}
#   HUBOT_JIRA_TRANSITIONS_MAP [{"name":"triage","jira":"Triage"},{"name":"icebox","jira":"Icebox"},{"name":"backlog","jira":"Backlog"},{"name":"devready","jira":"Selected for Development"},{"name":"inprogress","jira":"In Progress"},{"name":"design","jira":"Design Triage"}]
#   HUBOT_JIRA_PRIORITIES_MAP [{"name":"Blocker","id":"1"},{"name":"Critical","id":"2"},{"name":"Major","id":"3"},{"name":"Minor","id":"4"},{"name":"Trivial","id":"5"}]
#   HUBOT_GITHUB_TOKEN - Github Application Token
#   HUBOT_GITHUB_ORG - Github Organization or Github User
#
# Author:
#   ndaversa

_ = require "underscore"
moment = require "moment"

Config = require "./config"
Github = require "./github"
Help = require "./help"
Jira = require "./jira"
Adapters = require "./adapters"
Utils = require "./utils"

class JiraBot

  @JIRA_ROOM_TICKET_MENTIONS: "jira-room-ticket-mentions"

  constructor: (@robot) ->
    return new JiraBot @robot unless @ instanceof JiraBot
    Utils.robot = @robot
    Utils.JiraBot = @
    @robot.brain.once "loaded", =>
      @mentions = @robot.brain.get(JiraBot.JIRA_ROOM_TICKET_MENTIONS) or {}

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
    message = @filterAttachmentsForPreviousMentions context, message if filter
    @adapter.send context, message

  filterAttachmentsForPreviousMentions: (context, message) ->
    return message if _(message).isString()
    return message unless @mentions?
    return message unless message.attachments?.length > 0
    room = context.message.room

    removals = []
    for attachment in message.attachments
      keep = yes
      key = attachment.author_name?.trim().toUpperCase()
      continue unless Config.ticket.regex.test key
      if @mentions[room]
        if time = @mentions[room].tickets[key]
          keep = moment().isAfter time
      else
        @mentions[room] = tickets: {}
      @mentions[room].tickets[key] = moment().add 5, 'minutes' if keep

      #Cleanup other mention expiries
      for r, obj of @mentions
        for k, t of @mentions[r].tickets
          if moment().isAfter t
            delete @mentions[r].tickets[k]

      @robot.brain.set JiraBot.JIRA_ROOM_TICKET_MENTIONS, @mentions
      @robot.brain.save()

      unless keep
        @robot.logger.info "Supressing ticket attachment for #{key} in #{room}"
        removals.push attachment

    message.attachments = _(message.attachments).difference removals
    return message

  matchJiraTicket: (message) ->
    if message.match?
      matches = message.match(Config.ticket.regexGlobal)
    else if message.message?.rawText?.match?
      matches = message.message.rawText.match(Config.ticket.regexGlobal)

    if matches and matches[0]
      return matches
    else
      if message.message?.rawMessage?.attachments?
        attachments = message.message.rawMessage.attachments
        for attachment in attachments
          if attachment.text?
            matches = attachment.text.match(Config.ticket.regexGlobal)
            if matches and matches[0]
              return matches
    return false

  prepareResponseForJiraTickets: (msg) ->
    Promise.all(msg.match.map (key) =>
      _attachments = []
      Jira.Create.fromKey(key).then (ticket) ->
        _attachments.push ticket.toAttachment()
        ticket
      .then (ticket) ->
        Github.PullRequests.fromKey ticket.key
      .then (prs) ->
        prs.toAttachment()
      .then (attachments) ->
        _attachments.push a for a in attachments
        _attachments
    ).then (attachments) =>
      @send msg, attachments: _(attachments).flatten()
    .catch (error) =>
      @send msg, "#{error}"
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

    @robot.on "JiraWebhookTicketDone", (ticket, event) =>
      @adapter.dm Utils.lookupChatUsersWithJira(ticket.watchers),
        text: """
          A ticket you are watching has been marked `Done`.
        """
        author: event.user
        footer: disableDisclaimer
        attachments: [ ticket.toAttachment no ]

    @robot.on "JiraWebhookTicketComment", (ticket, comment) =>
      @adapter.dm Utils.lookupChatUsersWithJira(ticket.watchers),
        text: """
          A ticket you are watching has a new comment from #{comment.author.displayName}:
          ```
          #{comment.body}
          ```
        """
        author: comment.author
        footer: disableDisclaimer
        attachments: [ ticket.toAttachment no ]

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

    # Assigned
    @robot.on "JiraWebhookTicketAssigned", (ticket, user, event) =>
      @adapter.dm user,
        text: """
          You were assigned to a ticket by #{event.user.displayName}:
        """
        author: event.user
        footer: disableDisclaimer
        attachments: [ ticket.toAttachment no ]

  registerEventListeners: ->

    #Find Matches (for cross-script usage)
    @robot.on "JiraFindTicketMatches", (msg, cb) =>
      cb @matchJiraTicket msg

    #Prepare Responses For Tickets (for cross-script usage)
    @robot.on "JiraPrepareResponseForTickets", (msg) =>
      @prepareResponseForJiraTickets msg

    #Create
    @robot.on "JiraTicketCreated", (ticket, room) =>
      @send message: room: room,
        text: "Ticket created"
        attachments: [ ticket.toAttachment no ]

    @robot.on "JiraTicketCreationFailed", (error, room) =>
      robot.logger.error error.stack
      @send message: room: room, "Unable to create ticket #{error}"

    #Created in another room
    @robot.on "JiraTicketCreatedElsewhere", (ticket, msg) =>
      channel = @robot.adapter.client.getChannelGroupOrDMByName msg.message.room
      for r in Utils.lookupRoomsForProject ticket.fields.project.key
        @send message: room: r,
          text: "Ticket created in <##{channel.id}|#{channel.name}> by <@#{msg.message.user.id}>"
          attachments: [ ticket.toAttachment no ]

    #Clone
    @robot.on "JiraTicketCloned", (ticket, room, clone, msg) =>
      channel = @robot.adapter.client.getChannelGroupOrDMByName msg.message.room
      @send message: room: room,
        text: "Ticket created: Cloned from #{clone} in <##{channel.id}|#{channel.name}> by <@#{msg.message.user.id}>"
        attachments: [ ticket.toAttachment no ]

    @robot.on "JiraTicketCloneFailed", (error, ticket, room) =>
      robot.logger.error error.stack
      channel = @robot.adapter.client.getChannelGroupOrDMByName room
      @send message: room: room, "Unable to clone `#{ticket}` to the <\##{channel.id}|#{channel.name}> project :sadpanda:\n```#{error}```"

    #Transition
    @robot.on "JiraTicketTransitioned", (ticket, transition, room, includeAttachment=no) =>
      @send message: room: room,
        text: "Transitioned #{ticket.key} to `#{transition.to.name}`"
        attachments: [ ticket.toAttachment no ] if includeAttachment

    @robot.on "JiraTicketTransitionFailed", (error, room) =>
      robot.logger.error error.stack
      @send message: room: room, "#{error}"

    #Assign
    @robot.on "JiraTicketAssigned", (ticket, user, room, includeAttachment=no) =>
      @send message: room: room,
        text: "Assigned <@#{user.id}> to #{ticket.key}"
        attachments: [ ticket.toAttachment no ] if includeAttachment

    @robot.on "JiraTicketUnassigned", (ticket, room, includeAttachment=no) =>
      @send message: room: room,
        text: "#{ticket.key} is now unassigned"
        attachments: [ ticket.toAttachment no ] if includeAttachment

    @robot.on "JiraTicketAssignmentFailed", (error, room) =>
      @robot.logger.error error.stack
      @send message: room: room, "#{error}"

    #Watch
    @robot.on "JiraTicketWatched", (ticket, user, room, includeAttachment=no) =>
      @send message: room: room,
        text: "Added <@#{user.id}> as a watcher on #{ticket.key}"
        attachments: [ ticket.toAttachment no ] if includeAttachment

    @robot.on "JiraTicketUnwatched", (ticket, user, room, includeAttachment=no) =>
      @send message: room: room,
        text: "Removed <@#{user.id}> as a watcher on #{ticket.key}"
        attachments: [ ticket.toAttachment no ] if includeAttachment

    @robot.on "JiraTicketWatchFailed", (error, room) =>
      @robot.logger.error error.stack
      @send message: room: room, "#{error}"

    #Rank
    @robot.on "JiraTicketRanked", (ticket, direction, room, includeAttachment=no) =>
      @send message: room: room,
        text: "Ranked #{ticket.key} to `#{direction}`"
        attachments: [ ticket.toAttachment no ] if includeAttachment

    @robot.on "JiraTicketRankFailed", (error, room) =>
      @robot.logger.error error.stack
      @send message: room: room, "#{error}"

    #Labels
    @robot.on "JiraTicketLabelled", (ticket, room, includeAttachment=no) =>
      @send message: room: room,
        text: "Added labels to #{ticket.key}"
        attachments: [ ticket.toAttachment no ] if includeAttachment

    @robot.on "JiraTicketLabelFailed", (error, room) =>
      @robot.logger.error error.stack
      @send message: room: room, "#{error}"

    #Comments
    @robot.on "JiraTicketCommented", (ticket, room, includeAttachment=no) =>
      @send message: room: room,
        text: "Added comment to #{ticket.key}"
        attachments: [ ticket.toAttachment no ] if includeAttachment

    @robot.on "JiraTicketCommentFailed", (error, room) =>
      @robot.logger.error error.stack
      @send message: room: room, "#{error}"

  registerRobotResponses: ->
    #Help
    @robot.respond Config.help.regex, (msg) =>
      msg.finish()
      [ __, topic] = msg.match
      @send msg, Help.forTopic topic, @robot

    #Enable/Disable Watch Notifications
    @robot.respond Config.watch.notificationsRegex, (msg) =>
      msg.finish()
      [ __, state ] = msg.match
      switch state
        when "allow", "start", "enable"
          @adapter.enableNotificationsFor msg.message.user
          @send msg, """
          JIRA Watch notifications have been *enabled*

          You will start receiving notifications for JIRA tickets you are watching

          If you wish to _disable_ them just send me this message:
          > jira disable notifications
          """
        when "disallow", "stop", "disable"
          @adapter.disableNotificationsFor msg.message.user
          @send msg, """
          JIRA Watch notifications have been *disabled*

          You will no longer receive notifications for JIRA tickets you are watching

          If you wish to _enable_ them again just send me this message:
          > jira enable notifications
          """
    #Search
    @robot.respond Config.search.regex, (msg) =>
      msg.finish()
      [__, query] = msg.match
      room = msg.message.room
      project = Config.maps.projects[room]
      Jira.Search.withQueryForProject(query, project, msg)
      .then (results) =>
        attachments = (ticket.toAttachment() for ticket in results.tickets)
        @send msg,
          text: results.text
          attachments: attachments
        , no
      .catch (error) =>
        @send msg, "Unable to search for `#{query}` :sadpanda:"
        @robot.logger.error error.stack

    #Transition
    if Config.maps.transitions
      @robot.hear Config.transitions.regex, (msg) =>
        msg.finish()
        [ __, key, toState ] = msg.match
        Jira.Transition.forTicketKeyToState key, toState, msg, no

    #Clone
    @robot.hear Config.clone.regex, (msg) =>
      msg.finish()
      [ __, ticket, channel ] = msg.match
      project = Config.maps.projects[channel]
      Jira.Clone.fromTicketKeyToProject ticket, project, channel, msg

    #Watch
    @robot.hear Config.watch.regex, (msg) =>
      msg.finish()
      [ __, key, remove, person ] = msg.match

      if remove
        Jira.Watch.forTicketKeyRemovePerson key, person, msg, no
      else
        Jira.Watch.forTicketKeyForPerson key, person, msg, no

    #Rank
    @robot.hear Config.rank.regex, (msg) =>
      msg.finish()
      [ __, key, direction ] = msg.match
      Jira.Rank.forTicketKeyByDirection key, direction, msg, no

    #Labels
    @robot.hear Config.labels.addRegex, (msg) =>
      msg.finish()
      [ __, key ] = msg.match
      {input: input} = msg.match
      labels = []
      labels = (input.match(Config.labels.regex).map((label) -> label.replace('#', '').trim())).concat(labels)

      Jira.Labels.forTicketKeyWith key, labels, msg, no

    #Comment
    @robot.hear Config.comment.regex, (msg) =>
      msg.finish()
      [ __, key, comment ] = msg.match

      Jira.Comment.forTicketKeyWith key, comment, msg, no

    #Subtask
    @robot.respond Config.subtask.regex, (msg) =>
      msg.finish()
      [ __, key, summary ] = msg.match
      Jira.Create.subtaskFromKeyWith key, summary, msg

    #Assign
    @robot.hear Config.assign.regex, (msg) =>
      msg.finish()
      [ __, key, remove, person ] = msg.match

      if remove
        Jira.Assign.forTicketKeyToUnassigned key, msg, no
      else
        Jira.Assign.forTicketKeyToPerson key, person, msg, no

    #Create
    @robot.respond Config.commands.regex, (msg) =>
      [ __, project, command, summary ] = msg.match
      room = project or msg.message.room
      project = Config.maps.projects[room]
      type = Config.maps.types[command]

      unless project
        channels = []
        for team, key of Config.maps.projects
          channel = @robot.adapter.client.getChannelGroupOrDMByName team
          channels.push " <\##{channel.id}|#{channel.name}>" if channel
        return msg.reply "#{type} must be submitted in one of the following project channels: #{channels}"

      Jira.Create.with project, type, summary, msg

    #Mention ticket by url
    @robot.hear Config.jira.urlRegexGlobal, (msg) =>
      [ __, ticket ] = msg.match
      matches = msg.match.map (match) ->
        match.match(Config.jira.urlRegex)[1]
      msg.match = matches
      @prepareResponseForJiraTickets msg

    #Mention ticket by key
    @robot.listen @matchJiraTicket, @prepareResponseForJiraTickets.bind @

module.exports = JiraBot
