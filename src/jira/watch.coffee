Config = require "../config"
User = require "./user"
Utils = require "../utils"

class Watch
  @forTicketKeyForPerson: (key, person, context, includeAttachment=no, remove=no, emit=yes) ->
    person = if person is "me" or not person then context.message.user.name else person

    key = key.toUpperCase()
    chatUser = Utils.lookupChatUser person

    if chatUser?.profile?.email?
      User.withEmail(chatUser.profile.email)
      .then (user) ->
        Utils.fetch "#{Config.jira.url}/rest/api/2/issue/#{key}/watchers#{if remove then "?username=#{user.name}" else ""}",
          method: if remove then "DELETE" else "POST"
          body: JSON.stringify user.name unless remove
      .then ->
        Create = require "./create"
        Create.fromKey key
      .then (ticket) ->
        if remove
          context.robot.emit "JiraTicketUnwatched", ticket, chatUser, context, includeAttachment if emit
        else
          context.robot.emit "JiraTicketWatched", ticket, chatUser, context, includeAttachment if emit
      .catch (error) ->
        context.robot.emit "JiraTicketWatchFailed", error, context if emit
        Promise.reject error
    else
      error = "Cannot find chat user `#{person}`"
      context.robot.emit "JiraTicketWatchFailed", error, context if emit
      Promise.reject error

  @forTicketKeyRemovePerson: (key, person, context, includeAttachment=no, emit) ->
    Watch.forTicketKeyForPerson key, person, context, includeAttachment, yes, emit

module.exports = Watch
