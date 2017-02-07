_ = require "underscore"

Config = require "../config"
Utils = require "../utils"

class Transition

  @forTicketToState: (ticket, toState, context, includeAttachment=no, emit=yes) ->
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
        context.robot.emit "JiraTicketTransitioned", ticket, transition, context, includeAttachment if emit
        text: "<@#{context.message.user.id}> transitioned this ticket to #{transition.to.name}"
        fallback: "@#{context.message.user.name} transitioned this ticket to #{transition.to.name}"
      .catch (error) ->
        context.robot.emit "JiraTicketTransitionFailed", error, context if emit
        Promise.reject error
    else
      error = "<#{Config.jira.url}/browse/#{ticket.key}|#{ticket.key}> is a `#{ticket.fields.issuetype.name}` and does not support transitioning from `#{ticket.fields.status.name}` to `#{type.jira}`"
      context.robot.emit "JiraTicketTransitionFailed", error, context if emit
      Promise.reject error

  @forTicketKeyToState: (key, toState, context, includeAttachment=no, emit=yes) ->
    Create = require "./create"
    Create.fromKey(key)
    .then (ticket) ->
      Transition.forTicketToState ticket, toState, context, includeAttachment, emit

module.exports = Transition
