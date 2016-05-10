_ = require "underscore"
Fuse = require "fuse.js"
fetch = require "node-fetch"
cache = require "memory-cache"

Config = require "./config"

class Utils
  @robot: null

  @fetch: (url, opts) ->
    options =
      headers:
        "X-Atlassian-Token": "no-check"
        "Content-Type": "application/json"
        "Authorization": 'Basic ' + new Buffer("#{Config.jira.username}:#{Config.jira.password}").toString('base64')
    options = _(options).extend opts

    Utils.robot.logger.debug "Fetching: #{url}"
    fetch(url,options).then (response) ->
      if response.status >= 200 and response.status < 300
        return response
      else
        error = new Error "#{response.statusText}: #{response.url.split("?")[0]}"
        error.response = response
        throw error
    .then (response) ->
      length = response.headers.get 'content-length'
      response.json() unless length is "0" or length is 0
    .catch (error) ->
      Utils.robot.logger.error error
      Utils.robot.logger.error error.stack
      try
        error.response.json().then (json) ->
          Utils.robot.logger.error JSON.stringify json
          message = "\n`#{error}`"
          message += "\n`#{v}`" for k,v of json.errors
          throw message
      catch e
        throw error

  @lookupRoomsForProject: (project) ->
    results = _(Config.maps.projects).pick (p) -> p is project
    _(results).keys()

  @lookupChatUser: (username) ->
    users = Utils.robot.brain.users()
    result = (users[user] for user of users when users[user].name is username)
    if result?.length is 1
      return result[0]
    return null

  @lookupUserWithJira: (jira, fallback=no) ->
    users = Utils.robot.brain.users()
    result = (users[user] for user of users when users[user].email_address is jira.emailAddress) if jira
    if result?.length is 1
      return if fallback then result[0].name else "<@#{result[0].id}>"
    else if jira
      return jira.displayName
    else
      return "Unassigned"

  @lookupChatUsersWithJira: (jiraUsers, message) ->
    jiraUsers = [ jiraUsers ] unless _(jiraUsers).isArray()
    chatUsers = []
    for jiraUser in jiraUsers when jiraUser
      user = Utils.lookupChatUserWithJira jiraUser
      chatUsers.push user if user
    return chatUsers

  @lookupChatUserWithJira: (jira) ->
    users = Utils.robot.brain.users()
    result = (users[user] for user of users when users[user].email_address is jira.emailAddress) if jira
    return result[0] if result?.length is 1
    return null

  @lookupUserWithGithub: (user) ->
    return undefined unless user?.login

    users = Utils.robot.brain.users()
    users = _(users).keys().map (id) ->
      u = users[id]
      id: u.id
      name: u.name
      real_name: u.real_name

    f = new Fuse users,
      keys: ['real_name']
      shouldSort: yes
      verbose: no

    results = f.search user.login
    result = if results? and results.length >=1 then results[0] else undefined
    return result

  @buildQueryString: (params) ->
    "?#{("#{encodeURIComponent k}=#{encodeURIComponent v}" for k,v of params when v).join "&"}"

  @fuzzyFind: (term, arr, keys, opts) ->
    f = new Fuse arr, _(keys: keys, shouldSort: yes, threshold: 0.3).extend opts
    results = f.search term
    result = if results? and results.length >=1 then results[0]

  @cache:
    put: (key, value, time=Config.cache.default.expiry) -> cache.put key, value, time
    get: cache.get

module.exports = Utils
