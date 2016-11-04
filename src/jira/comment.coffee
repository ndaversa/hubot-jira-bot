Config = require "../config"
Utils = require "../utils"

class Comment

  @forTicketWith: (ticket, comment, msg, includeAttachment=no, emit=yes) ->
    room = Utils.JiraBot.adapter.getRoomName msg
    Utils.fetch "#{Config.jira.url}/rest/api/2/issue/#{ticket.key}/comment",
      method: "POST"
      body: JSON.stringify
        body:"""
          #{comment}

          Comment left by #{msg.message.user.name} in ##{room} on #{msg.robot.adapterName}
          #{Utils.JiraBot.adapter.getPermalink msg}
        """
    .then ->
      Utils.robot.logger.debug "#{ticket.key}:Comment", msg.message.user.profile.email
      Utils.cache.put "#{ticket.key}:Comment", msg.message.user.profile.email
      msg.robot.emit "JiraTicketCommented", ticket, msg.message.room, includeAttachment if emit
    .catch (error) ->
      msg.robot.emit "JiraTicketCommentFailed", error, msg.message.room if emit
      Promise.reject error

  @forTicketKeyWith: (key, comment, msg, includeAttachment=no, emit=yes) ->
    Create = require "./create"
    Create.fromKey(key)
    .then (ticket) ->
      Comment.forTicketWith ticket, comment, msg, includeAttachment, emit

module.exports = Comment
