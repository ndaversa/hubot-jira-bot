Config = require "../config"
Utils = require "../utils"

class User

  @withEmail: (email) ->
    Utils.fetch("#{Config.jira.url}/rest/api/2/user/search?username=#{email}")
    .then (user) ->
      jiraUser = user[0] if user and user.length is 1
      throw "Cannot find jira user with #{email}" unless jiraUser
      jiraUser

module.exports = User
