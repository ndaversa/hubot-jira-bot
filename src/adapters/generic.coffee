_ = require "underscore"
Utils = require "../utils"

class GenericAdapter
  @JIRA_NOTIFICATIONS_DISABLED: "jira-notifications-disabled"
  @JIRA_DM_COUNTS: "jira-dm-counts"

  constructor: (@robot) ->
    @disabledUsers = null
    @dmCounts = null

    @robot.brain.once "loaded", =>
      @disabledUsers = @robot.brain.get(GenericAdapter.JIRA_NOTIFICATIONS_DISABLED) or []
      @dmCounts = @robot.brain.get(GenericAdapter.JIRA_DM_COUNTS) or {}

  disableNotificationsFor: (user) ->
    @robot.logger.info "Disabling JIRA notifications for #{user.name}"
    @disabledUsers.push user.id
    @robot.brain.set GenericAdapter.JIRA_NOTIFICATIONS_DISABLED, _(@disabledUsers).unique()
    @robot.brain.save()

  enableNotificationsFor: (user) ->
    @robot.logger.info "Enabling JIRA notifications for #{user.name}"
    @disabledUsers = _(@disabledUsers).without user.id
    @robot.brain.set GenericAdapter.JIRA_NOTIFICATIONS_DISABLED, @disabledUsers
    @robot.brain.save()

  incrementDMCountFor: (user) ->
    return unless @dmCounts?
    return unless user?.id?

    @dmCounts[user.id] ||= 0
    @dmCounts[user.id]++
    @robot.brain.set GenericAdapter.JIRA_DM_COUNTS, @dmCounts
    @robot.brain.save()

  getDMCountFor: (user) ->
    return 0 unless @dmCounts?
    return 0 unless user?.id?
    @dmCounts[user.id] ||= 0
    return @dmCounts[user.id]

  send: (context, message) ->
    room = @getRoom context
    return unless room

    if _(message).isString()
      payload = message
    else if message.text or message.attachments
      payload = ""

      if message.text
        payload += "#{message.text}\n"

      if message.attachments
        for attachment in message.attachments
          payload += "#{attachment.fallback}\n"
    else
      Utils.Stats.increment "jirabot.message.empty"
      return @robot.logger.error "Unable to find a message to send", message

    @robot.send room: room.id, payload

  dm: (users, message) ->
    users = [ users ] unless _(users).isArray()
    for user in users when user
      if _(@disabledUsers).contains user.id
        Utils.Stats.increment "jirabot.surpress.notification"
        @robot.logger.debug "JIRA Notification surpressed for #{user.name}"
      else
        if message.author? and user.profile?.email is message.author.emailAddress
          @robot.logger.debug "JIRA Notification surpressed for #{user.name} because it would be a self-notification"
          continue
        message.text += "\n#{message.footer}" if message.text and message.footer and @getDMCountFor(user) < 3
        @send message: room: user.id, _(message).pick "attachments", "text"
        @incrementDMCountFor user

  getPermalink: (msg) -> ""

  normalizeContext: (context) ->
    if _(context).isString()
      normalized = message: room: context
    else if context?.room
      normalized = message: context
    else if context?.message?.room
      normalized = context
    normalized

  getRoom: (context) ->
    context = @normalizeContext context
    id: context.message.room
    name: context.message.room

  getRoomName: (context) ->
    room = @getRoom context
    room.name

  getUsers: ->
    @robot.brain.users()

module.exports = GenericAdapter
