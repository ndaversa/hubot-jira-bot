# Description:
#  Quickly file JIRA tickets with hubot
#  Also listens for mention of tickets and responds with information
#
# Dependencies:
# - moment
# - octokat
# - node-fetch
#
# Configuration:
#   HUBOT_JIRA_URL (format: "https://jira-domain.com:9090")
#   HUBOT_JIRA_USERNAME
#   HUBOT_JIRA_PASSWORD
#   HUBOT_JIRA_TYPES_MAP  \{\"story\":\"Story\ \/\ Feature\",\"bug\":\"Bug\",\"task\":\"Task\"\}
#   HUBOT_JIRA_PROJECTS_MAP  \{\"web\":\"WEB\",\"android\":\"AN\",\"ios\":\"IOS\",\"platform\":\"PLAT\"\}
#   HUBOT_GITHUB_TOKEN - Github Application Token
#
# Author:
#   ndaversa

fetch = require 'node-fetch'
moment = require 'moment'
Octokat = require 'octokat'

module.exports = (robot) ->
  jiraUrl = process.env.HUBOT_JIRA_URL
  jiraUsername = process.env.HUBOT_JIRA_USERNAME
  jiraPassword = process.env.HUBOT_JIRA_PASSWORD
  headers =
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

  parseJSON = (response) ->
    return response.json()

  checkStatus = (response) ->
    if response.status >= 200 and response.status < 300
      return response
    else
      error = new Error(response.statusText)
      error.response = response
      throw error

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

    fetch("#{jiraUrl}/rest/api/2/user/search?username=#{msg.message.user.email_address}", headers: headers)
    .then (res) ->
      checkStatus res
    .then (res) ->
      parseJSON res
    .then (user) ->
      reporter = user[0] if user and user.length is 1
      quoteRegex = /`{1,3}([^]*?)`{1,3}/
      labelsRegex = /\s+#\S+\s?/g
      labels = []
      [__, command, message] = msg.match

      desc = message.match(quoteRegex)[1] if quoteRegex.test(message)
      message = message.replace(quoteRegex, "") if desc

      if labelsRegex.test(message)
        labels = (message.match(labelsRegex).map((label) -> label.replace('#', '').trim())).concat(labels)
        message = message.replace(labelsRegex, "")

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
      msg.send "<@#{msg.message.user.id}> Ticket created: #{jiraUrl}/browse/#{json.key}"
    .catch (error) ->
      msg.send "<@#{msg.message.user.id}> Unable to create ticket #{error}"


  robot.listen(
    # Match for JIRA tickets
    (message) ->
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
    # Callback when matches
    (msg) ->
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
            *[#{json.key}] - #{json.fields.summary}*
            Status: #{json.fields.status.name}
            Assignee: #{lookupUserWithJira json.fields.assignee}
            Reporter: #{lookupUserWithJira json.fields.reporter}
            JIRA: #{jiraUrl}/browse/#{json.key}
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
        msg.send "*[Error]* #{error}"
  )

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
