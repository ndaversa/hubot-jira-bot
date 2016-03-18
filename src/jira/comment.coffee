Config = require "../config"
Utils = require "../utils"

class Comment

  @forTicketWith: (ticket, comment, msg, includeAttachment=no) ->
    Utils.fetch "#{Config.jira.url}/rest/api/2/issue/#{ticket.key}/comment",
      method: "POST"
      body: JSON.stringify
        body:"""
          #{comment}

          Comment left by #{msg.message.user.name} in ##{msg.message.room} on #{msg.robot.adapterName}
          https://#{msg.robot.adapter.client.team.domain}.slack.com/archives/#{msg.message.room}/p#{msg.message.id.replace '.', ''}
        """
    .then ->
      msg.robot.emit "JiraTicketCommented", ticket, msg.message.room, includeAttachment
    .catch (error) ->
      msg.robot.emit "JiraTicketCommentFailed", error, msg.message.room
      Promise.reject error

  @forTicketKeyWith: (key, comment, msg, includeAttachment=no) ->
    Create = require "./create"
    Create.fromKey(key)
    .then (ticket) ->
      Comment.forTicketWith ticket, comment, msg, includeAttachment

module.exports = Comment
