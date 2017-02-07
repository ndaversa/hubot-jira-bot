Config = require "../config"
Utils = require "../utils"

class Comment

  @forTicketWith: (ticket, comment, context, includeAttachment=no, emit=yes) ->
    room = Utils.JiraBot.adapter.getRoomName context
    Utils.fetch "#{Config.jira.url}/rest/api/2/issue/#{ticket.key}/comment",
      method: "POST"
      body: JSON.stringify
        body:"""
          #{comment}

          Comment left by #{context.message.user.name} in ##{room} on #{context.robot.adapterName}
          #{Utils.JiraBot.adapter.getPermalink context}
        """
    .then ->
      Utils.robot.logger.debug "#{ticket.key}:Comment", context.message.user.profile.email
      Utils.cache.put "#{ticket.key}:Comment", context.message.user.profile.email
      context.robot.emit "JiraTicketCommented", ticket, context, includeAttachment if emit
    .catch (error) ->
      context.robot.emit "JiraTicketCommentFailed", error, context if emit
      Promise.reject error

  @forTicketKeyWith: (key, comment, context, includeAttachment=no, emit=yes) ->
    Create = require "./create"
    Create.fromKey(key)
    .then (ticket) ->
      Comment.forTicketWith ticket, comment, context, includeAttachment, emit

module.exports = Comment
