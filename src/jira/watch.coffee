Config = require "../config"
User = require "./user"
Utils = require "../utils"

class Watch
  @forTicketKeyForPerson: (key, person, msg, includeAttachment=no, remove=no, emit=yes) ->
    person = if person is "me" or not person then msg.message.user.name else person

    key = key.toUpperCase()
    chatUser = Utils.lookupChatUser person

    if chatUser
      User.withEmail(chatUser.email_address)
      .then (user) ->
        Utils.fetch "#{Config.jira.url}/rest/api/2/issue/#{key}/watchers#{if remove then "?username=#{user.name}" else ""}",
          method: if remove then "DELETE" else "POST"
          body: JSON.stringify user.name unless remove
      .then ->
        Create = require "./create"
        Create.fromKey key
      .then (ticket) ->
        if remove
          msg.robot.emit "JiraTicketUnwatched", ticket, chatUser, msg.message.room, includeAttachment if emit
        else
          msg.robot.emit "JiraTicketWatched", ticket, chatUser, msg.message.room, includeAttachment if emit
      .catch (error) ->
        msg.robot.emit "JiraTicketWatchFailed", error, msg.message.room if emit
        Promise.reject error
    else
      error = "Cannot find chat user `#{person}`"
      msg.robot.emit "JiraTicketWatchFailed", error, msg.message.room if emit
      Promise.reject error

  @forTicketKeyRemovePerson: (key, person, msg, includeAttachment=no, emit) ->
    Watch.forTicketKeyForPerson key, person, msg, includeAttachment, yes, emit

module.exports = Watch
