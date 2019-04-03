Config = require "../config"
User = require "./user"
Utils = require "../utils"

class Assign

  @forTicketToPerson: (ticket, person, context, includeAttachment=no, emit=yes) ->
    person = if person is "me" then context.message.user.name else person
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
        Utils.robot.logger.debug "#{ticket.key}:Assigned", context.message.user.email_address
        Utils.cache.put "#{ticket.key}:Assigned", context.message.user.email_address
        context.robot.emit "JiraTicketAssigned", ticket, chatUser, context, includeAttachment if emit
        text: "<@#{chatUser.id}> is now assigned to this ticket"
        fallback: "@#{chatUser.name} is now assigned to this ticket"
      .catch (error) ->
        context.robot.emit "JiraTicketAssignmentFailed", error, context if emit
        Promise.reject error
    else
      error = "Cannot find chat user `#{person}`"
      context.robot.emit "JiraTicketAssignmentFailed", error, context if emit
      Promise.reject error

  @forTicketKeyToPerson: (key, person, context, includeAttachment=no, emit=yes) ->
    Create = require "./create"
    Create.fromKey(key)
    .then (ticket) ->
      Assign.forTicketToPerson ticket, person, context, includeAttachment, emit

  @forTicketKeyToUnassigned: (key, context, includeAttachment=no, emit=yes) ->
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
        context.robot.emit "JiraTicketUnassigned", ticket, context, no if emit

module.exports = Assign
