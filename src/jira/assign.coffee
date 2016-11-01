Config = require "../config"
User = require "./user"
Utils = require "../utils"

class Assign

  @forTicketToPerson: (ticket, person, msg, includeAttachment=no, emit=yes) ->
    person = if person is "me" then msg.message.user.name else person
    chatUser = Utils.lookupChatUser person

    if chatUser?.profile?.email?
      User.withEmail(chatUser.profile.email)
      .then (user) ->
        Utils.fetch "#{Config.jira.url}/rest/api/2/issue/#{ticket.key}",
          method: "PUT"
          body: JSON.stringify
            fields:
              assignee:
                name: user.name
      .then ->
        Create = require "./create"
        Create.fromKey ticket.key
      .then (ticket) ->
        Utils.robot.logger.debug "#{ticket.key}:Assigned", msg.message.user.profile.email
        Utils.cache.put "#{ticket.key}:Assigned", msg.message.user.profile.email
        msg.robot.emit "JiraTicketAssigned", ticket, chatUser, msg.message.room, includeAttachment if emit
        text: "<@#{chatUser.id}> is now assigned to this ticket"
        fallback: "@#{chatUser.name} is now assigned to this ticket"
      .catch (error) ->
        msg.robot.emit "JiraTicketAssignmentFailed", error, msg.message.room if emit
        Promise.reject error
    else
      error = "Cannot find chat user `#{person}`"
      msg.robot.emit "JiraTicketAssignmentFailed", error, msg.message.room if emit
      Promise.reject error

  @forTicketKeyToPerson: (key, person, msg, includeAttachment=no, emit=yes) ->
    Create = require "./create"
    Create.fromKey(key)
    .then (ticket) ->
      Assign.forTicketToPerson ticket, person, msg, includeAttachment, emit

  @forTicketKeyToUnassigned: (key, msg, includeAttachment=no, emit=yes) ->
    Utils.fetch "#{Config.jira.url}/rest/api/2/issue/#{key}",
      method: "PUT"
      body: JSON.stringify
        fields:
          assignee:
            name: null
    .then ->
      Create = require "./create"
      Create.fromKey(key)
      .then (ticket) ->
        msg.robot.emit "JiraTicketUnassigned", ticket, msg.message.room, no if emit

module.exports = Assign
