Config = require "../config"
Jira = require "../jira"
Utils = require "../utils"

class Slack
  constructor: (@robot) ->
    # Since the slack client used by hubot-slack has not yet been updated
    # to the latest version, we do not get events for reactions.
    # Also there doesn't seem to be a better way to get a reference to
    # a Slack message after it is posted, so...
    #
    # This processes all messages from Slack and emits events for the three
    # things we care about
    #   1. When we get our Ticket Created message
    #        - so we can add our default bot reactions to it
    #   2. When a reaction is added by someone
    #   3. When a reaction is removed by someone
    @robot.adapter.client.on "raw_message", (msg) =>
      @onJiraTicketCreationMessage msg if msg.type is "message" and msg.user is @robot.adapter.self.id and msg.text is Config.ticket.CREATED_TEXT
      return unless msg.item_user is @robot.adapter.self.id
      return unless msg.user isnt @robot.adapter.self.id
      if msg.type is "reaction_added"
        @onReactionAdded msg
      else if msg.type is "reaction_removed"
        @onReactionRemoved msg

  onJiraTicketCreationMessage: (msg) =>
    reactions = ["point_up_2", "point_down", "watch", "raising_hand", "soon", "fast_forward"]
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
        when "watch"
          Jira.Watch.forTicketKeyRemovePerson key, null,
            robot: @robot
            message:
              room: msg.item.channel
              user: @robot.adapter.client.getUserByID(msg.user)
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
              user: @robot.adapter.client.getUserByID(msg.user)
        when "watch"
          Jira.Watch.forTicketKeyForPerson key, null,
            robot: @robot
            message:
              room: msg.item.channel
              user: @robot.adapter.client.getUserByID(msg.user)
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
          Jira.Assign.forTicketKeyToPerson key, @robot.adapter.client.getUserByID(msg.user).name,
            robot: @robot
            message:
              room: msg.item.channel
              user: msg.user

  getTicketKeyInChannelByTs: (channel, ts) ->
    switch channel[0]
      when "G"
        endpoint = "groups"
      when "C"
        endpoint = "channels"
      else
        return

    params =
      channel: channel
      latest: ts
      oldest: ts
      inclusive: 1
      count: 1
      token: Config.slack.token

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
      @robot.logger.info error

module.exports = Slack
