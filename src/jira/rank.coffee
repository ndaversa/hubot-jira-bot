Config = require "../config"
Utils = require "../utils"

class Rank

  @forTicketForDirection: (ticket, direction, context, includeAttachment=no, emit=yes) ->
    direction = direction.toLowerCase()

    switch direction
      when "up", "top" then direction = "Top"
      when "down", "bottom" then direction = "Bottom"
      else
        error = "`#{direction}` is not a valid rank direction"
        context.robot.emit "JiraTicketRankFailed", error, context if emit
        return Promise.reject error

    Utils.fetch("#{Config.jira.url}/secure/Rank#{direction}.jspa?issueId=#{ticket.id}")
    context.robot.emit "JiraTicketRanked", ticket, direction, context, includeAttachment if emit

  @forTicketKeyByDirection: (key, direction, context, includeAttachment=no, emit=yes) ->
    Create = require "./create"
    Create.fromKey(key)
    .then (ticket) ->
      Rank.forTicketForDirection ticket, direction, context, includeAttachment, emit

module.exports = Rank
