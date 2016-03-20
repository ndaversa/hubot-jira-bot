_ = require "underscore"

class GenericAdapter
  constructor: (@robot) ->

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

module.exports = GenericAdapter
