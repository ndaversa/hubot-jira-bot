_ = require "underscore" 

Config = require "../config"
Utils = require "../utils"

class User

  @withEmail: (email) ->
    Utils.fetch("#{Config.jira.url}/rest/api/2/user/search?username=#{email}")
    .then (users) ->
      jiraUser = _(users).findWhere emailAddress: email if users and users.length > 0
      throw "Cannot find jira user with #{email}, trying myself" unless jiraUser
      jiraUser
    .catch (error) ->
      Utils.robot.logger.error error
      Utils.Stats.increment "jirabot.user.lookup.email.failed"
      Utils.fetch("#{Config.jira.url}/rest/api/2/myself")

  @withUsername: (username) ->
    Utils.fetch("#{Config.jira.url}/rest/api/2/user?username=#{username}")
    .catch (error) ->
      Utils.Stats.increment "jirabot.user.lookup.username.failed"
      Utils.robot.logger.error "Cannot find jira user with #{username}, trying myself"
      Utils.fetch("#{Config.jira.url}/rest/api/2/myself")

module.exports = User
