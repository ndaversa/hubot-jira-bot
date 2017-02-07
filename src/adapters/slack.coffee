_ = require "underscore"

Config = require "../config"
Jira = require "../jira"
Utils = require "../utils"
GenericAdapter = require "./generic"

class Slack extends GenericAdapter
  constructor: (@robot) ->
    super @robot
    @queue = {}

    @robot.router.post "/hubot/slack-events", (req, res) =>
      try
        payload = JSON.parse req.body.payload
        return unless payload.token is Config.slack.verification.token
        return @robot.emit "SlackEvents", payload, res unless @shouldJiraBotHandle payload
      catch e
        @robot.logger.debug e
        Utils.Stats.increment "jirabot.webhook.failed"
        return

      @onButtonActions(payload).then ->
        res.json payload.original_message
      .catch (error) ->
        @robot.logger.error error

  getRoom: (context) ->
    context = @normalizeContext context
    room = @robot.adapter.client.rtm.dataStore.getChannelOrGroupByName context.message.room
    room = @robot.adapter.client.rtm.dataStore.getChannelGroupOrDMById context.message.room unless room
    room

  getUsers: ->
    @robot.adapter.client.rtm.dataStore.users

  send: (context, message) ->
    payload = text: ""
    room = @getRoom context
    return unless room

    if _(message).isString()
      payload.text = message
    else
      payload = _(payload).chain().extend(message).pick("text", "attachments").value()

    if Config.slack.verification.token and payload.attachments?.length > 0
      attachments = []
      for a in payload.attachments
        attachments.push a
        attachments.push @buttonAttachmentsForState "mention", a if a and a.type is "JiraTicketAttachment"
      payload.attachments = attachments

    payload.text = " " if payload.attachments?.length > 0 and payload.text.length is 0
    if payload.text.length > 0
      @robot.adapter.send 
        room: room.id
        message: thread_ts: context.message.thread_ts
      , payload 

  shouldJiraBotHandle: (context) ->
    id = context.callback_id
    matches = id.match Config.ticket.regexGlobal

    if matches and matches[0]
      return yes
    else if ~id.indexOf "JiraBotDuplicate"
      return yes
    else
      return no

  onButtonActions: (payload) ->
    Promise.all payload.actions.map (action) => @handleButtonAction payload, action

  handleDuplicateReponse: (payload, action) ->
    id = payload.callback_id.split(":")[1]
    msg = payload.original_message
    msg.attachments.pop()
    if item = @queue[id]
      clearTimeout item.timer
      delete @queue[id]

      if action.name is "create" and action.value is "yes"
        msg.attachments.push text: "Creating ticket..."
        item.action()

      if action.name is "create" and action.value is "no"
        msg.attachments.push text: "Ticket creation has been cancelled"
      Utils.Stats.increment "jirabot.slack.button.duplicate.#{action.name}.#{action.value}"

    return Promise.resolve()

  handleButtonAction: (payload, action) ->
    key = payload.callback_id
    return @handleDuplicateReponse payload, action if ~key.indexOf "JiraBotDuplicate"

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
      Utils.Stats.increment "jirabot.slack.button.#{action.name}"

  getPermalink: (context) ->
    team = _(context.robot.adapter.client.rtm.dataStore.teams).pairs()
    if domain = team[0]?[1]?.domain
      "https://#{domain}.slack.com/archives/#{context.message.room}/p#{context.message.id.replace '.', ''}"
    else
      ""

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

  detectForDuplicates: (project, type, summary, context) ->
    original = summary
    create = -> Jira.Create.with project, type, original, context
    { summary } = Utils.extract.all summary

    Jira.Search.withQueryForProject(summary, project, context, 20)
    .then (results) =>
      if duplicate = Utils.detectPossibleDuplicate summary, results.tickets
        now = Date.now()
        @queue[now] =
          timer: setTimeout =>
            create()
            delete @queue[now]
          , Config.duplicates.timeout
          action: create

        attachments = [ duplicate.toAttachment no ]
        attachments.push
          fallback: "Unable to display quick action buttons"
          attachment_type: "default"
          callback_id: "JiraBotDuplicate:#{now}"
          text: """
            There are potential duplicates of this issue.
            If you do not respond, the ticket will be created in #{Config.duplicates.timeout/1000} seconds

            What would you like to do?
          """
          actions: [
            name: "create"
            text: "Create anyways"
            style: "primary"
            type: "button"
            value: "yes"
          ,
            name: "create"
            text: "Do not create"
            style: "danger"
            type: "button"
            value: "no"
          ]

        @send context,
          text: results.text
          attachments: attachments
        , no
      else
        create()
    .catch ->
      create()

module.exports = Slack
