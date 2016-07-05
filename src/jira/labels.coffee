_ = require "underscore"

Config = require "../config"
Utils = require "../utils"

class Labels

  @forTicketWith: (ticket, labels, msg, includeAttachment=no, emit=yes) ->
    Utils.fetch "#{Config.jira.url}/rest/api/2/issue/#{ticket.key}",
      method: "PUT"
      body: JSON.stringify
        fields: labels: labels
    .then ->
      msg.robot.emit "JiraTicketLabelled", ticket, msg.message.room, includeAttachment if emit
    .catch (error) ->
      msg.robot.emit "JiraTicketLabelFailed", error, msg.message.room if emit
      Promise.reject error

  @forTicketKeyWith: (key, labels, msg, includeAttachment=no, emit=yes) ->
    Create = require "./create"
    Create.fromKey(key)
    .then (ticket) ->
      labels = _(labels).union ticket.fields.labels
      Labels.forTicketWith ticket, labels, msg, includeAttachment, emit

module.exports = Labels
