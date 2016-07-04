_ = require "underscore"

Config = require "../config"
Jira = require "../jira"
Utils = require "../utils"
GenericAdapter = require "./generic"

class Slack extends GenericAdapter
  constructor: (@robot) ->
    super @robot

    @robot.router.post "/hubot/slack-events", (req, res) =>
      return unless req.body?
      try
        payload = JSON.parse req.body.payload
        return unless payload.token is Config.slack.verification.token
      catch e
        return

      @onButtonActions(payload).then ->
        res.json payload.original_message

    # Since the slack client used by hubot-slack has not yet been updated
    # to the latest version, we do not get events for reactions.
    # Also there doesn't seem to be a better way to get a reference to
    # a Slack message after it is posted, so...
    #
    # This processes all messages from Slack and emits events for the three
    # things we care about
    #   1. When we get a message with a Jira attachment
    #        - so we can add our default bot reactions to it
    #   2. When a reaction is added by someone
    #   3. When a reaction is removed by someone
    @robot.adapter.client.on "raw_message", (msg) =>
      @onJiraTicketMessageAttachment msg if @hasJiraAttachment msg
      return unless msg.item_user is @robot.adapter.self.id
      return unless msg.user isnt @robot.adapter.self.id
      msg.user = @robot.brain.users()[msg.user]
      if msg.type is "reaction_added"
        @onReactionAdded msg
      else if msg.type is "reaction_removed"
        @onReactionRemoved msg

  hasJiraAttachment: (msg) ->
    return no unless msg.type is "message"
    return no unless msg.user is @robot.adapter.self.id
    return no unless msg.attachments?.length is 1
    attachment = msg.attachments[0]
    return no unless attachment.title_link?.length > 0
    return Config.jira.urlRegex.test attachment.title_link

  send: (context, message) ->
    payload = channel: context.message.room
    if _(message).isString()
      payload.text = message
    else
      payload = _(payload).extend message

    if Config.slack.verification.token and payload.attachments?.length > 0
      attachments = []
      for ja in payload.attachments
        attachments.push ja
        attachments.push @buttonAttachmentsForState "mention", ja if ja.type is "JiraTicketAttachment"
      payload.attachments = attachments
    rc = @robot.adapter.customMessage payload

    # Could not find existing conversation
    # so client bails on sending see issue: https://github.com/slackhq/hubot-slack/issues/256
    # detect the bail by checking the response and attempt
    # a fallback using adapter.send
    if rc is undefined
      text = payload.text
      text += "\n#{a.fallback}" for a in payload.attachments
      @robot.adapter.send context.message, text

  onJiraTicketMessageAttachment: (msg) =>
    reactions = ["point_up_2", "point_down", "eyes", "raising_hand", "soon", "fast_forward"]
    dispatchNextReaction = ->
      reaction = reactions.shift()
      return unless reaction
      params =
        channel: msg.channel
        timestamp: msg.ts
        name: reaction
        token: Config.slack.token
      Utils.fetch("https://slack.com/api/reactions.add#{Utils.buildQueryString params}").then dispatchNextReaction
    dispatchNextReaction()

  onReactionRemoved: (msg) ->
    @getTicketKeyInChannelByTs(msg.item.channel, msg.item.ts)
    .then (key) ->
      switch msg.reaction
        when "eyes"
          Jira.Watch.forTicketKeyRemovePerson key, null,
            robot: @robot
            message:
              room: msg.item.channel
              user: msg.user
        when "raising_hand"
          Jira.Assign.forTicketKeyToUnassigned key,
            robot: @robot
            message:
              room: msg.item.channel
              user: msg.user

  onReactionAdded: (msg) ->
    @getTicketKeyInChannelByTs(msg.item.channel, msg.item.ts)
    .then (key) ->
      switch msg.reaction
        when "point_up_2", "point_down"
          direction = if msg.reaction is "point_up_2" then "up" else "down"
          Jira.Rank.forTicketKeyByDirection key, direction,
            robot: @robot
            message:
              room: msg.item.channel
              user: msg.user
        when "eyes"
          Jira.Watch.forTicketKeyForPerson key, null,
            robot: @robot
            message:
              room: msg.item.channel
              user: msg.user
        when "soon", "fast_forward"
          term = if msg.reaction is "soon" then "selected" else "progress"
          result = Utils.fuzzyFind term, Config.maps.transitions, ['jira']
          if result
            Jira.Transition.forTicketKeyToState key, result.name,
              robot: @robot
              message:
                room: msg.item.channel
                user: msg.user
        when "raising_hand"
          Jira.Assign.forTicketKeyToPerson key, msg.user.name,
            robot: @robot
            message:
              room: msg.item.channel
              user: msg.user

  onButtonActions: (payload) ->
    Promise.all payload.actions.map (action) => @handleButtonAction payload, action

  handleButtonAction: (payload, action) ->
    return new Promise (resolve, reject) =>
      key = payload.callback_id
      user = payload.user
      msg = payload.original_message
      envelope =
        robot: emit: -> #Discard emitted messages, slack attachments are enough communication
        message: user: user

      switch action.name
        when "rank"
          Jira.Rank.forTicketKeyByDirection key, "up", envelope
          msg.attachments.push
            text: "<@#{user.id}|#{user.name}> ranked this ticket to the top"
          resolve()
        when "watch"
          Jira.Create.fromKey(key)
          .then (ticket) =>
            watchers = Utils.lookupChatUsersWithJira ticket.watchers
            if _(watchers).findWhere(id: user.id)
              msg.attachments.push
                text: "<@#{user.id}|#{user.name}> has stopped watching this ticket"
              Jira.Watch.forTicketKeyRemovePerson key, null, envelope
            else
              msg.attachments.push
                text: "<@#{user.id}|#{user.name}> is now watching this ticket"
              Jira.Watch.forTicketKeyForPerson key, user.name, envelope
            resolve()
        when "assign"
          Jira.Create.fromKey(key)
          .then (ticket) =>
            assignee = Utils.lookupChatUserWithJira ticket.fields.assignee
            if assignee and assignee.id is user.id
              Jira.Assign.forTicketKeyToUnassigned key, envelope
              msg.attachments.push
                text: "<@#{user.id}|#{user.name}> has unassigned themself"
            else
              Jira.Assign.forTicketKeyToPerson key, user.name, envelope
              msg.attachments.push
                text: "<@#{user.id}|#{user.name}> is now assigned to this ticket"
            resolve()
        when "devready", "inprogress", "review", "done"
          result = Utils.fuzzyFind action.value, Config.maps.transitions, ['jira']
          if result
            msg.attachments.push @buttonAttachmentsForState action.name,
              key: key
              text: "<@#{user.id}|#{user.name}> transitioned this ticket to #{result.jira}"
            Jira.Transition.forTicketKeyToState key, result.name, envelope
          resolve()

  getTicketKeyInChannelByTs: (channel, ts) ->
    switch channel[0]
      when "G"
        endpoint = "groups"
      when "C"
        endpoint = "channels"
      when "D"
        endpoint = "im"
      else
        return Promise.reject()

    params =
      channel: channel
      latest: ts
      oldest: ts
      inclusive: 1
      count: 1
      token: Config.slack.api.token

    Utils.fetch("https://slack.com/api/#{endpoint}.history#{Utils.buildQueryString params}")
    .then (json) ->
      message = json.messages?[0]
      throw "Cannot find message at timestamp provided" unless message? and message.type is "message"
      attachment = message.attachments?[0]
      throw "Message does not contain an attachment with a title link" unless attachment?.title_link?
      ticket = attachment.title_link.split "#{Config.jira.url}/browse/"
      throw "Cannot find jira ticket" unless ticket and ticket.length is 2
      return ticket[1]
    .catch (error) ->
      @robot.logger.error error

  getPermalink: (msg) ->
    "https://#{msg.robot.adapter.client.team.domain}.slack.com/archives/#{msg.message.room}/p#{msg.message.id.replace '.', ''}"

  buttonAttachmentsForState: (state="mention", details) ->
    watch =
      name: "watch"
      text: "Watch"
      type: "button"
      value: "watch"
      style: "primary"

    assign =
      name: "assign"
      text: "Assign to me"
      type: "button"
      value: "assign"

    devready =
      name: "devready"
      text: "Dev Ready"
      type: "button"
      value: "selected"

    inprogress =
      name: "inprogress"
      text: "In Progress"
      type: "button"
      value: "progress"

    rank =
      name: "rank"
      text: "Rank Top"
      type: "button"
      value: "top"

    review =
      name: "review"
      text: "Review"
      type: "button"
      value: "review"

    done =
      name: "done"
      text: "Done"
      type: "button"
      style: "primary"
      value: "done"

    switch state
      when "inprogress"
        actions = [ review, done ]
      when "review"
        actions = [ done ]
      when "done"
        actions = [ devready, inprogress ]
      when "mention"
        actions = [ watch, assign, devready, inprogress, rank ]

    fallback: "Unable to display quick action buttons"
    attachment_type: "default"
    callback_id: details.author_name or details.key
    color: details.color
    actions: actions
    text: details.text

module.exports = Slack
