Utils = require "../utils"

class Webhook
  constructor: (@robot) ->
    @robot.router.post "/hubot/jira-events", (req, res) =>
      return unless req.body?
      event = req.body
      return unless event.issue.fields.watches.watchCount > 0

      if event.comment?
        return @onComment event
      else if event.changelog?
        return @onChangelog event

  statusChangeType: (status) ->
    acceptedTypes = [
      keywords: "done completed resolved fixed"
      name: "JiraWebhookTicketDone"
    ,
      keywords: "progress"
      name: "JiraWebhookTicketInProgress"
    ]
    return Utils.fuzzyFind status, acceptedTypes, ['keywords']

  onChangelog: (event) ->
    return unless event.changelog.items?.length > 0

    for item in event.changelog.items
      continue unless item.field is "status"
      status = @statusChangeType item.toString.toLowerCase()
      unless status
        @robot.logger.info "#{event.issue.key}: Ignoring transition to '#{item.toString}'"
        continue

      Create = require "./create"
      Create.fromKey(event.issue.key)
      .then (ticket) =>
        @robot.logger.info "#{event.issue.key}: Emitting #{status.name} because of the transition to '#{item.toString}'"
        @robot.emit status.name, ticket

  onComment: (event) ->
    Create = require "./create"
    Create.fromKey(event.issue.key)
    .then (ticket) =>
      @robot.emit "JiraWebhookTicketComment", ticket, event.comment


module.exports = Webhook
