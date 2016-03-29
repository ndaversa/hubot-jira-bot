_ = require "underscore"

Utils = require "../utils"

class GenericAdapter
  constructor: (@robot) ->
    @disabledUsers = null
    @robot.brain.once "loaded", =>
      @disabledUsers = @robot.brain.get("jira-notifications-disabled") or []

  disableNotificationsFor: (user) ->
    @robot.logger.info "Disabling JIRA notifications for #{user.name}"
    @disabledUsers.push user.id
    @robot.brain.set "jira-notifications-disabled", @disabledUsers

  enableNotificationsFor: (user) ->
    @robot.logger.info "Enabling JIRA notifications for #{user.name}"
    @disabledUsers = _(@disabledUsers).without user.id
    @robot.brain.set "jira-notifications-disabled", @disabledUsers

  send: (context, message) ->
    if _(message).isString()
      payload = message
    else if message.attachments
      payload = ""
      payload += "#{message.text}\n" if message.text
      for attachment in message.attachments
        payload += "#{attachment.fallback}\n"
    else
      return @robot.logger.error "Unable to find a message to send", message

    @robot.send room: context.message.room, payload

  dm: (jiraUsers, message) ->
    for jiraUser in jiraUsers
      user = Utils.lookupChatUserWithJira jiraUser
      if user and not _(@disabledUsers).contains user.id
        @send message: room: user.name, message
      else if not user
        @robot.logger.error "Unable to find chat user from jira #{jira}"
      else
        @robot.logger.info "JIRA Notification surpressed for #{user.name}"

module.exports = GenericAdapter
