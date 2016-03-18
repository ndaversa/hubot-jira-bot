_ = require "underscore"

Config = require "../config"
Utils = require "../utils"

class Transition

  @forTicketToState: (ticket, toState, msg, includeAttachment=no) ->
    type = _(Config.maps.transitions).find (type) -> type.name is toState
    transition = ticket.transitions.find (state) -> state.to.name.toLowerCase() is type.jira.toLowerCase()
    if transition
      Utils.fetch "#{Config.jira.url}/rest/api/2/issue/#{ticket.key}/transitions",
        method: "POST"
        body: JSON.stringify
          transition:
            id: transition.id
      .then ->
        Create = require "./create"
        Create.fromKey ticket.key
      .then (ticket) ->
        msg.robot.emit "JiraTicketTransitioned", ticket, transition, msg.message.room, includeAttachment
      .catch (error) ->
        msg.robot.emit "JiraTicketTransitionFailed", error, msg.message.room
        Promise.reject error
    else
      error = "<#{Config.jira.url}/browse/#{ticket.key}|#{ticket.key}> is a `#{ticket.fields.issuetype.name}` and does not support transitioning from `#{ticket.fields.status.name}` to `#{type.jira}`"
      msg.robot.emit "JiraTicketTransitionFailed", error, msg.message.room
      Promise.reject error

  @forTicketKeyToState: (key, toState, msg, includeAttachment=no) ->
    Create = require "./create"
    Create.fromKey(key)
    .then (ticket) ->
      Transition.forTicketToState ticket, toState, msg, includeAttachment

module.exports = Transition
