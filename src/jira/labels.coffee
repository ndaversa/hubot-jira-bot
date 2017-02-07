_ = require "underscore"

Config = require "../config"
Utils = require "../utils"

class Labels

  @forTicketWith: (ticket, labels, context, includeAttachment=no, emit=yes) ->
    Utils.fetch "#{Config.jira.url}/rest/api/2/issue/#{ticket.key}",
      method: "PUT"
      body: JSON.stringify
        fields: labels: labels
    .then ->
      context.robot.emit "JiraTicketLabelled", ticket, context, includeAttachment if emit
    .catch (error) ->
      context.robot.emit "JiraTicketLabelFailed", error, context if emit
      Promise.reject error

  @forTicketKeyWith: (key, labels, context, includeAttachment=no, emit=yes) ->
    Create = require "./create"
    Create.fromKey(key)
    .then (ticket) ->
      labels = _(labels).union ticket.fields.labels
      Labels.forTicketWith ticket, labels, context, includeAttachment, emit

module.exports = Labels
