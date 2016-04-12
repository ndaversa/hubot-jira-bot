Config = require "../config"
Utils = require "../utils"

class User

  @withEmail: (email) ->
    Utils.fetch("#{Config.jira.url}/rest/api/2/user/search?username=#{email}")
    .then (user) ->
      jiraUser = user[0] if user and user.length is 1
      throw "Cannot find jira user with #{email}, trying myself" unless jiraUser
      jiraUser
    .catch (error) ->
      Utils.robot.logger.error error
      Utils.fetch("#{Config.jira.url}/rest/api/2/myself")

  @withUsername: (username) ->
    Utils.fetch("#{Config.jira.url}/rest/api/2/user?username=#{username}")
    .catch (error) ->
      Utils.robot.logger.error "Cannot find jira user with #{username}, trying myself"
      Utils.fetch("#{Config.jira.url}/rest/api/2/myself")

module.exports = User
