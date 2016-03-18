Config = require "../config"
Utils = require "../utils"

class Rank

  @forTicketForDirection: (ticket, direction, msg, includeAttachment=no) ->
    direction = direction.toLowerCase()

    switch direction
      when "up", "top" then direction = "Top"
      when "down", "bottom" then direction = "Bottom"
      else
        error = "`#{direction}` is not a valid rank direction"
        msg.robot.emit "JiraTicketRankFailed", error, msg.message.room
        return Promise.reject error

    Utils.fetch("#{Config.jira.url}/secure/Rank#{direction}.jspa?issueId=#{ticket.id}")
    msg.robot.emit "JiraTicketRanked", ticket, direction, msg.message.room, includeAttachment

  @forTicketKeyByDirection: (key, direction, msg, includeAttachment=no) ->
    Create = require "./create"
    Create.fromKey(key)
    .then (ticket) ->
      Rank.forTicketForDirection ticket, direction, msg, includeAttachment

module.exports = Rank
