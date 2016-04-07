_ = require "underscore"

Config = require "../config"
Utils = require "../utils"

class Labels

  @forTicketWith: (ticket, labels, msg, includeAttachment=no) ->
    Utils.fetch "#{Config.jira.url}/rest/api/2/issue/#{ticket.key}",
      method: "PUT"
      body: JSON.stringify
        fields: labels: labels
    .then ->
      msg.robot.emit "JiraTicketLabelled", ticket, msg.message.room, includeAttachment
    .catch (error) ->
      msg.robot.emit "JiraTicketLabelFailed", error, msg.message.room
      Promise.reject error

  @forTicketKeyWith: (key, labels, msg, includeAttachment=no) ->
    Create = require "./create"
    Create.fromKey(key)
    .then (ticket) ->
      labels = _(labels).union ticket.fields.labels
      Labels.forTicketWith ticket, labels, msg, includeAttachment

module.exports = Labels
