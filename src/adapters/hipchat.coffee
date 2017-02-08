_ = require "underscore"

Utils = require "../utils"
GenericAdapter = require "./generic"

class Hipchat extends GenericAdapter
  constructor: (@robot) ->
    super @robot

  send: (context, message) ->
    envelope = @getEnvelope(context)
    return unless envelope

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

    @robot.adapter.send envelope, payload

  getEnvelope: (context) ->
    return context.envelope

  getUsers: ->
    @robot.brain.data.users

  # Hipchat adapter stores users in the brain
  #{
  # "users": {
  #   "0000000": {
  #     "id": "0000000",
  #     "jid": "111111_0000000@chat.hipchat.com",
  #     "name": "John Doe",
  #     "mention_name": "JohnDoe",
  #     "email_address": "johndoe@example.com"
  #   },
  getUserEmail: (user) ->
    user.email_address

module.exports = Hipchat