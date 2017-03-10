_ = require "underscore"

Config = require "../config"
Utils = require "../utils"
User = require "./user"

class Webhook
  constructor: (@robot) ->
    @robot.router.post "/hubot/jira-events", (req, res) =>
      return unless req.body?
      event = req.body
      if event.changelog?
        @onChangelog event
      else if event.comment?
        @onComment event
      else if event.webhookEvent is "jira:issue_created"
        @onCreate event

      res.send 'OK'

  onChangelog: (event) ->
    return unless event.changelog.items?.length > 0
    for item in event.changelog.items
      switch item.field
        when "status"
          @onStatusChange event, item
        when "description"
          @onDescriptionChange event, item
        when "assignee"
          @onAssigneeChange event, item

  onComment: (event) ->
    if Config.mention.regex.test event.comment.body
      @onAtHandleMention event, event.comment.body.match(Config.mention.regex)[1], event.comment.body
    if Config.jira.mentionRegex.test event.comment.body
      @onJiraMention event, event.comment.body.match(Config.jira.mentionRegex)[1], event.comment.body
    Create = require "./create"
    regex = /rest\/api\/2\/issue\/(\d*)\//
    [ __, key] = event.comment.self.match regex
    Create.fromKey(key)
    .then (ticket) =>
      if author = Utils.cache.get "#{ticket.key}:Comment"
        User.withEmail(author)
        .then (user) ->
          event.comment.author = user
          ticket
      else
        ticket
    .then (ticket) =>
      @robot.emit "JiraWebhookTicketComment", ticket, event.comment

  onCreate: (event) ->
    @onDescriptionChange event,
      toString: event.issue.fields.description or ""
      fromString: ""

    if event.issue.fields.assignee
      @onAssigneeChange event,
        field: "assignee"
        fieldtype: "jira"
        to: event.issue.fields.assignee.name

  onJiraMention: (event, username, context) ->
    chatUser = null
    User.withUsername(username)
    .then (jiraUser) ->
      chatUser = Utils.lookupChatUserWithJira jiraUser
      Promise.reject() unless chatUser
      Create = require "./create"
      Create.fromKey(event.issue.key)
    .then (ticket) =>
      @robot.emit "JiraWebhookTicketMention", ticket, chatUser, event, context

  onAtHandleMention: (event, handle, context) ->
    chatUser = Utils.lookupChatUser handle
    return unless chatUser
    Create = require "./create"
    Create.fromKey(event.issue.key)
    .then (ticket) =>
      @robot.emit "JiraWebhookTicketMention", ticket, chatUser, event, context

  onDescriptionChange: (event, item) ->
    if Config.mention.regex.test item.toString
      previousMentions = item.fromString.match Config.mention.regexGlobal
      latestMentions = item.toString.match Config.mention.regexGlobal
      newMentions = _(latestMentions).difference previousMentions
      for mention in newMentions
        handle = mention.match(Config.mention.regex)[1]
        @onAtHandleMention event, handle, item.toString

    if Config.jira.mentionRegex.test item.toString
      previousMentions = item.fromString.match Config.jira.mentionRegexGlobal
      latestMentions = item.toString.match Config.jira.mentionRegexGlobal
      newMentions = _(latestMentions).difference previousMentions
      for mention in newMentions
        username = mention.match(Config.jira.mentionRegex)[1]
        @onJiraMention event, username, item.toString

  onAssigneeChange: (event, item) ->
    return unless item.to

    chatUser = null
    User.withUsername(item.to)
    .then (jiraUser) ->
      chatUser = Utils.lookupChatUserWithJira jiraUser
      Promise.reject() unless chatUser
      Create = require "./create"
      Create.fromKey(event.issue.key)
    .then (ticket) =>
      if author = Utils.cache.get "#{ticket.key}:Assigned"
        User.withEmail(author)
        .then (user) ->
          event.user = user
          ticket
      else
        ticket
    .then (ticket) =>
      @robot.emit "JiraWebhookTicketAssigned", ticket, chatUser, event

  onStatusChange: (event, item) ->
    states = [
      keywords: "done completed resolved fixed merged"
      name: "JiraWebhookTicketDone"
    ,
      keywords: "progress"
      name: "JiraWebhookTicketInProgress"
    ,
      keywords: "review reviewed"
      name: "JiraWebhookTicketInReview"
    ]
    status = Utils.fuzzyFind item.toString.toLowerCase(), states, ['keywords']
    return @robot.logger.debug "#{event.issue.key}: Ignoring transition to '#{item.toString}'" unless status

    Create = require "./create"
    Create.fromKey(event.issue.key)
    .then (ticket) =>
      @robot.logger.debug "#{event.issue.key}: Emitting #{status.name} because of the transition to '#{item.toString}'"
      @robot.emit status.name, ticket, event

module.exports = Webhook
