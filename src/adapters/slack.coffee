_ = require "underscore"

Config = require "../config"
Jira = require "../jira"
Utils = require "../utils"
GenericAdapter = require "./generic"

class Slack extends GenericAdapter
  constructor: (@robot) ->
    super @robot

    @robot.router.post "/hubot/slack-events", (req, res) =>
      try
        payload = JSON.parse req.body.payload
        return unless payload.token is Config.slack.verification.token
        return @robot.emit "SlackEvents", payload, res unless @shouldJiraBotHandle payload
      catch e
        @robot.logger.debug e
        return

      @onButtonActions(payload).then ->
        res.json payload.original_message
      .catch (error) ->
        @robot.logger.error error

  send: (context, message) ->
    payload = channel: context.message.room
    if _(message).isString()
      payload.text = message
    else
      payload = _(payload).extend message

    if Config.slack.verification.token and payload.attachments?.length > 0
      attachments = []
      for a in payload.attachments
        attachments.push a
        attachments.push @buttonAttachmentsForState "mention", a if a and a.type is "JiraTicketAttachment"
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

  shouldJiraBotHandle: (msg) ->
    matches = msg.callback_id.match Config.ticket.regexGlobal

    if matches and matches[0]
      return yes
    else
      return no

  onButtonActions: (payload) ->
    Promise.all payload.actions.map (action) => @handleButtonAction payload, action

  handleButtonAction: (payload, action) ->
    return new Promise (resolve, reject) =>
      key = payload.callback_id
      user = payload.user
      msg = payload.original_message
      envelope = message: user: user

      switch action.name
        when "rank"
          Jira.Rank.forTicketKeyByDirection key, "up", envelope, no, no
          msg.attachments.push
            text: "<@#{user.id}> ranked this ticket to the top"
          resolve()
        when "watch"
          Jira.Create.fromKey(key)
          .then (ticket) =>
            watchers = Utils.lookupChatUsersWithJira ticket.watchers
            if _(watchers).findWhere(id: user.id)
              msg.attachments.push
                text: "<@#{user.id}> has stopped watching this ticket"
              Jira.Watch.forTicketKeyRemovePerson key, null, envelope, no, no
            else
              msg.attachments.push
                text: "<@#{user.id}> is now watching this ticket"
              Jira.Watch.forTicketKeyForPerson key, user.name, envelope, no, no, no
            resolve()
        when "assign"
          Jira.Create.fromKey(key)
          .then (ticket) =>
            assignee = Utils.lookupChatUserWithJira ticket.fields.assignee
            if assignee and assignee.id is user.id
              Jira.Assign.forTicketKeyToUnassigned key, envelope, no, no
              msg.attachments.push
                text: "<@#{user.id}> has unassigned themself"
            else
              Jira.Assign.forTicketKeyToPerson key, user.name, envelope, no, no
              msg.attachments.push
                text: "<@#{user.id}> is now assigned to this ticket"
            resolve()
        else
          result = Utils.fuzzyFind action.value, Config.maps.transitions, ['jira']
          if result
            msg.attachments.push @buttonAttachmentsForState action.name,
              key: key
              text: "<@#{user.id}> transitioned this ticket to #{result.jira}"
            Jira.Transition.forTicketKeyToState key, result.name, envelope, no, no
          else
            msg.attachments.push
              text: "Unable to to process #{action.name}"
          resolve()

  getPermalink: (msg) ->
    "https://#{msg.robot.adapter.client.team.domain}.slack.com/archives/#{msg.message.room}/p#{msg.message.id.replace '.', ''}"

  buttonAttachmentsForState: (state="mention", details) ->
    key = details.author_name or details.key
    return {} unless key and key.length > 0
    project = key.split("-")[0]
    return {} unless project
    buttons = Config.slack.buttons
    return {} unless buttons
    map = Config.slack.project.button.state.map[project] or Config.slack.project.button.state.map.default
    return {} unless map
    actions = []
    actions.push buttons[button] for button in map[state] if map[state]

    fallback: "Unable to display quick action buttons"
    attachment_type: "default"
    callback_id: key
    color: details.color
    actions: actions
    text: details.text

module.exports = Slack
