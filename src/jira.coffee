# Description:
#  Quickly file JIRA tickets with hubot
#  Also listens for mention of tickets and responds with information
#  And transition tickets as well
#
# Dependencies:
# - moment
# - octokat
# - node-fetch
# - underscore
#
# Configuration:
#   HUBOT_JIRA_URL (format: "https://jira-domain.com:9090")
#   HUBOT_JIRA_USERNAME
#   HUBOT_JIRA_PASSWORD
#   HUBOT_JIRA_TYPES_MAP  \{\"story\":\"Story\ \/\ Feature\",\"bug\":\"Bug\",\"task\":\"Task\"\}
#   HUBOT_JIRA_PROJECTS_MAP  \{\"web\":\"WEB\",\"android\":\"AN\",\"ios\":\"IOS\",\"platform\":\"PLAT\"\}
#   HUBOT_JIRA_TRANSITIONS_MAP \[\{\"name\":\"triage\",\"jira\":\"Triage\"\},\{\"name\":\"icebox\",\"jira\":\"Icebox\"\},\{\"name\":\"backlog\",\"jira\":\"Backlog\"\},\{\"name\":\"devready\",\"jira\":\"Selected\ for\ Development\"\},\{\"name\":\"inprogress\",\"jira\":\"In\ Progress\"\},\{\"name\":\"design\",\"jira\":\"Design\ Triage\"\}\]
#   HUBOT_JIRA_PRIORITIES_MAP \[\{\"name\":\"Blocker\",\"id\":\"1\"\},\{\"name\":\"Critical\",\"id\":\"2\"\},\{\"name\":\"Major\",\"id\":\"3\"\},\{\"name\":\"Minor\",\"id\":\"4\"\},\{\"name\":\"Trivial\",\"id\":\"5\"\}\]
#   HUBOT_GITHUB_TOKEN - Github Application Token
#
# Author:
#   ndaversa

_ = require 'underscore'
fetch = require 'node-fetch'
moment = require 'moment'
Octokat = require 'octokat'

module.exports = (robot) ->
  jiraUrl = process.env.HUBOT_JIRA_URL
  jiraUsername = process.env.HUBOT_JIRA_USERNAME
  jiraPassword = process.env.HUBOT_JIRA_PASSWORD
  headers =
      "X-Atlassian-Token": "no-check"
      "Content-Type": "application/json"
      "Authorization": 'Basic ' + new Buffer("#{jiraUsername}:#{jiraPassword}").toString('base64')

  token = process.env.HUBOT_GITHUB_TOKEN
  octo = new Octokat token: token

  types = JSON.parse process.env.HUBOT_JIRA_TYPES_MAP
  commands = (command for command, type of types).reduce (x,y) -> x + "|" + y
  commandsPattern = eval "/(#{commands}) ([^]+)/i"

  projects = JSON.parse process.env.HUBOT_JIRA_PROJECTS_MAP
  prefixes = (key for team, key of projects).reduce (x,y) -> x + "-|" + y
  jiraPattern = eval "/(^|\\s)(" + prefixes + "-)(\\d+)\\b/gi"

  jiraUrlRegexBase = "#{jiraUrl}/browse/".replace /[-\/\\^$*+?.()|[\]{}]/g, '\\$&'
  jiraUrlRegex = eval "/(?:#{jiraUrlRegexBase})((?:#{prefixes}-)\\d+)\\s*/i"
  jiraUrlRegexGlobal = eval "/(?:#{jiraUrlRegexBase})((?:#{prefixes}-)\\d+)\\s*/gi"

  transitions = null
  transitions = JSON.parse process.env.HUBOT_JIRA_TRANSITIONS_MAP if process.env.HUBOT_JIRA_TRANSITIONS_MAP
  transitionRegex = eval "/(?\:^|\\s)((?\:#{prefixes}-)(?\:\\d+))\\s+(?\:to\\s+|>\\s?)(#{(transitions.map (t) -> t.name).join "|"})/i" if transitions
  rankRegex = eval "/(?\:^|\\s)((?\:#{prefixes}-)(?\:\\d+)) rank (up|down|top|bottom)/i"
  assignRegex = eval "/(?\:^|\\s)((?\:#{prefixes}-)(?\:\\d+)) assign @?([\\w._]*)/i"
  commentRegex = eval "/(?\:^|\\s)((?\:#{prefixes}-)(?\:\\d+))\\s?(?\:<\\s?)([^]+)/i"

  priorities = JSON.parse process.env.HUBOT_JIRA_PRIORITIES_MAP if process.env.HUBOT_JIRA_PRIORITIES_MAP

  parseJSON = (response) ->
    return response.json()

  checkStatus = (response) ->
    if response.status >= 200 and response.status < 300
      return response
    else
      error = new Error(response.statusText)
      error.response = response
      throw error

  lookupSlackUser = (username) ->
    users = robot.brain.users()
    result = (users[user] for user of users when users[user].name is username)
    if result?.length is 1
      return result[0]
    return null

  lookupUserWithJira = (jira) ->
    users = robot.brain.users()
    result = (users[user] for user of users when users[user].email_address is jira.emailAddress) if jira
    if result?.length is 1
      return "<@#{result[0].id}>"
    else if jira
      return jira.displayName
    else
      return "Unassigned"

  lookupUserWithGithub = (github) ->
    users = robot.brain.get('github-users') or []
    result = (user for user in users when user.github is github.login) if github
    if result?.length is 1
      return "<@#{result[0].id}>"
    else if github
      return github.login
    else
      return "Unassigned"

  report = (project, type, msg) ->
    reporter = null
    [__, command, message] = msg.match

    if transitions
      shouldTransitionRegex = eval "/\\s+>\\s?(#{(transitions.map (t) -> t.name).join "|"})/i"
      if shouldTransitionRegex.test(message)
        [ __, toState] =  message.match shouldTransitionRegex

    fetch("#{jiraUrl}/rest/api/2/user/search?username=#{msg.message.user.email_address}", headers: headers)
    .then (res) ->
      checkStatus res
    .then (res) ->
      parseJSON res
    .then (user) ->
      reporter = user[0] if user and user.length is 1
      quoteRegex = /`{1,3}([^]*?)`{1,3}/
      labelsRegex = /\s+#\S+/g
      priorityRegex = eval "/\\s+!(#{(priorities.map (priority) -> priority.name).join '|'})\\b/i" if priorities
      labels = []

      desc = message.match(quoteRegex)[1] if quoteRegex.test(message)
      message = message.replace(quoteRegex, "") if desc
      message = message.replace(shouldTransitionRegex, "") if toState

      if labelsRegex.test(message)
        labels = (message.match(labelsRegex).map((label) -> label.replace('#', '').trim())).concat(labels)
        message = message.replace(labelsRegex, "")

      if priorities and priorityRegex.test(message)
        priority = message.match(priorityRegex)[1]
        priority = priorities.find (p) -> p.name.toLowerCase() is priority.toLowerCase()
        message = message.replace(priorityRegex, "")

      issue =
        fields:
          project:
            key: project
          summary: message
          labels: labels
          description: """
            #{(if desc then desc + "\n\n" else "")}
            Reported by #{msg.message.user.name} in ##{msg.message.room} on #{robot.adapterName}
            https://#{robot.adapter.client.team.domain}.slack.com/archives/#{msg.message.room}/p#{msg.message.id.replace '.', ''}
          """
          issuetype:
            name: type

      issue.fields.reporter = reporter if reporter
      issue.fields.priority = id: priority.id if priority
      issue
    .then (issue) ->
      fetch "#{jiraUrl}/rest/api/2/issue",
        headers: headers
        method: "POST"
        body: JSON.stringify issue
    .then (res) ->
      checkStatus res
    .then (res) ->
      parseJSON res
    .then (json) ->
      issue = json.key
      msg.send "<@#{msg.message.user.id}> Ticket created: #{jiraUrl}/browse/#{issue}"

      if toState
        msg.match = [ message, issue, toState ]
        handleTransitionRequest msg

    .catch (error) ->
      msg.send "<@#{msg.message.user.id}> Unable to create ticket #{error}"

  matchJiraTicket = (message) ->
    if message.match?
      matches = message.match(jiraPattern)
    else if message.message?.rawText?.match?
      matches = message.message.rawText.match(jiraPattern)

    if matches and matches[0]
      return matches
    else
      if message.message?.rawMessage?.attachments?
        attachments = message.message.rawMessage.attachments
        for attachment in attachments
          if attachment.text?
            matches = attachment.text.match(jiraPattern)
            if matches and matches[0]
              return matches
    return false

  buildJiraTicketOutput = (msg) ->
    Promise.all(msg.match.map (issue) ->
      message = ""
      id = ""
      ticket = issue.trim().toUpperCase()
      fetch("#{jiraUrl}/rest/api/2/issue/#{ticket}", headers: headers)
      .then (res) ->
        checkStatus res
      .then (res) ->
        parseJSON res
      .then (json) ->
        id = json.id
        message = """
          *[#{json.key}] - #{json.fields.summary.trim()}*
          #{jiraUrl}/browse/#{ticket}
          Status: #{json.fields.status.name}
          Assignee: #{lookupUserWithJira json.fields.assignee}
          Reporter: #{lookupUserWithJira json.fields.reporter}
        """
      .then (json) ->
        fetch("#{jiraUrl}/rest/api/2/issue/#{ticket}/watchers", headers: headers)
      .then (res) ->
        checkStatus res
      .then (res) ->
        parseJSON res
      .then (json) ->
        if json.watchCount > 0
          watchers = []
          watchers.push lookupUserWithJira watcher for watcher in json.watchers
          message += "\nWatchers: #{watchers.join ', '}"
      .then (json) ->
        fetch("#{jiraUrl}/rest/dev-status/1.0/issue/detail?issueId=#{id}&applicationType=github&dataType=branch", headers: headers)
      .then (res) ->
        checkStatus res
      .then (res) ->
        parseJSON res
      .then (json) ->
        if json.detail?[0]?.pullRequests
          return Promise.all json.detail[0].pullRequests.map (pr) ->
            if pr.status is "OPEN"
              orgAndRepo = pr.destination.url.split("github.com")[1].split('tree')[0].split('/')
              repo = octo.repos(orgAndRepo[1], orgAndRepo[2])
              return repo.pulls(pr.id.replace('#', '')).fetch()
      .then (prs) ->
        for pr in prs when pr
          message += """\n
            *[#{pr.title}]* +#{pr.additions} -#{pr.deletions}
            #{pr.htmlUrl}
            Updated: *#{moment(pr.updatedAt).fromNow()}*
            Status: #{if pr.mergeable then "Ready for merge" else "Needs rebase"}
            Assignee: #{lookupUserWithGithub pr.assignee}
          """
        return message
    ).then (messages) ->
      msg.send message for message in messages
    .catch (error) ->
      msg.send message for message in messages
      msg.send "*[Error]* #{error}"

  handleTransitionRequest = (msg) ->
    msg.finish()
    [ __, ticket, toState ] = msg.match
    ticket = ticket.toUpperCase()

    fetch("#{jiraUrl}/rest/api/2/issue/#{ticket}?expand=transitions.fields", headers: headers)
    .then (res) ->
      checkStatus res
    .then (res) ->
      parseJSON res
    .then (json) ->
      type = _(transitions).find (type) -> type.name is toState
      transition = json.transitions.find (state) -> state.to.name.toLowerCase() is type.jira.toLowerCase()
      if transition
        msg.send "<@#{msg.message.user.id}> Transitioning `#{ticket}` to `#{transition.to.name}`"
        fetch "#{jiraUrl}/rest/api/2/issue/#{ticket}/transitions",
          headers: headers
          method: "POST"
          body: JSON.stringify
            transition:
              id: transition.id
      else
        msg.send "#{ticket} is a `#{json.fields.issuetype.name}` and does not support transitioning from `#{json.fields.status.name}` to `#{type.jira}` :middle_finger:"
    .catch (error) ->
      msg.send "<@#{msg.message.user.id}> An error has occured: #{error}"

  handleRankRequest = (msg) ->
    msg.finish()
    [ __, ticket, direction ] = msg.match
    ticket = ticket.toUpperCase()
    direction = direction.toLowerCase()

    switch direction
      when "up", "top" then direction = "Top"
      when "down", "bottom" then direction = "Bottom"
      else throw "invalid direction"

    fetch("#{jiraUrl}/rest/api/2/issue/#{ticket}", headers: headers)
    .then (res) ->
      checkStatus res
    .then (res) ->
      parseJSON res
    .then (json) ->
      if json.id
        fetch("#{jiraUrl}/secure/Rank#{direction}.jspa?issueId=#{json.id}", headers: headers)
        #Note: this fetch returns HTML and cannot be validated/parsed for success
      else
        throw "Cannot find ticket `#{ticket}`"
    .then (res) ->
      checkStatus res
    .then () ->
      msg.send "<@#{msg.message.user.id}> Ranked `#{ticket}` to `#{direction}`"
    .catch (error) ->
      msg.send "<@#{msg.message.user.id}> An error has occured: #{error}"

  handleAssignRequest = (msg) ->
    msg.finish()
    [ __, ticket, person ] = msg.match
    person = if person is "me" then msg.message.user.name else person
    ticket = ticket.toUpperCase()
    slackUser = lookupSlackUser person

    if slackUser
      fetch("#{jiraUrl}/rest/api/2/user/search?username=#{slackUser.email_address}", headers: headers)
      .then (res) ->
        checkStatus res
      .then (res) ->
        parseJSON res
      .then (user) ->
        jiraUser = user[0] if user and user.length is 1
        if jiraUser
          fetch "#{jiraUrl}/rest/api/2/issue/#{ticket}",
            headers: headers
            method: "PUT"
            body: JSON.stringify
              fields:
                assignee:
                  name: jiraUser.name
        else
          msg.send "<@#{msg.message.user.id}> Cannot find jira user <@#{slackUser.id}>"
      .then () ->
        msg.send "<@#{msg.message.user.id}> Assigned <@#{slackUser.id}> to `#{ticket}`: #{jiraUrl}/browse/#{ticket}"
      .catch (error) ->
        msg.send "<@#{msg.message.user.id}> Error: `#{error}`"
    else
      msg.send "<@#{msg.message.user.id}> Cannot find slack user `#{person}`"

  addComment = (msg) ->
    msg.finish()
    [ __, ticket, comment ] = msg.match

    fetch "#{jiraUrl}/rest/api/2/issue/#{ticket}/comment",
      headers: headers
      method: "POST"
      body: JSON.stringify
        body:"""
          #{comment}

          Reported by #{msg.message.user.name} in ##{msg.message.room} on #{robot.adapterName}
          https://#{robot.adapter.client.team.domain}.slack.com/archives/#{msg.message.room}/p#{msg.message.id.replace '.', ''}
        """
    .then () ->
      msg.send "<@#{msg.message.user.id}> Added comment to `#{ticket}`: #{jiraUrl}/browse/#{ticket}"
    .catch (error) ->
      msg.send "<@#{msg.message.user.id}> Error: `#{error}`"

  robot.respond commandsPattern, (msg) ->
    [ __, command ] = msg.match
    room = msg.message.room
    project = projects[room]
    type = types[command]

    if not project
      channels = []
      for team, key of projects
        channel = robot.adapter.client.getChannelGroupOrDMByName team
        channels.push " <\##{channel.id}|#{channel.name}>" if channel
      return msg.reply "#{type} must be submitted in one of the following project channels:" + channels

    report project, type, msg

  robot.hear transitionRegex, handleTransitionRequest if transitions
  robot.hear rankRegex, handleRankRequest
  robot.hear assignRegex, handleAssignRequest
  robot.hear commentRegex, addComment

  robot.hear jiraUrlRegexGlobal, (msg) ->
    [ __, ticket ] = msg.match
    matches = msg.match.map (match) ->
      match.match(jiraUrlRegex)[1]
    msg.match = matches
    buildJiraTicketOutput msg

  robot.listen matchJiraTicket, buildJiraTicketOutput
