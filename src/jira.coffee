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
# - fuse.js
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
nodeFetch = require 'node-fetch'
moment = require 'moment'
Octokat = require 'octokat'
Fuse = require 'fuse.js'

module.exports = (robot) ->
  jiraUrl = process.env.HUBOT_JIRA_URL

  send = (context, message, prependUsername=yes) ->
    robot.adapter.customMessage
      channel: context.message.room
      text: "#{if prependUsername then "<@#{context.message.user.id}> " else ""}#{message}"

  fetch = (url, opts) ->
    robot.logger.info "Fetching: #{url}"
    options =
      headers:
        "X-Atlassian-Token": "no-check"
        "Content-Type": "application/json"
        "Authorization": 'Basic ' + new Buffer("#{process.env.HUBOT_JIRA_USERNAME}:#{process.env.HUBOT_JIRA_PASSWORD}").toString('base64')
    options = _(options).extend opts

    nodeFetch(url,options).then (response) ->
      if response.status >= 200 and response.status < 300
        return response
      else
        error = new Error(response.statusText)
        error.response = response
        throw error
    .then (response) ->
      response.json()
    .catch (error) ->
      robot.logger.error error.stack

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
    return if not github

    github.fetch().then (user) ->
      name = user.name or github.login
      users = robot.brain.users()
      users = _(users).keys().map (id) ->
        u = users[id]
        id: u.id
        name: u.name
        real_name: u.real_name

      f = new Fuse users,
        keys: ['real_name']
        shouldSort: yes
        verbose: no

      results = f.search name
      result = if results? and results.length >=1 then results[0] else undefined
      return result

  report = (project, type, msg) ->
    reporter = null
    assignee = null
    [__, command, message] = msg.match

    if transitions
      shouldTransitionRegex = eval "/\\s+>\\s?(#{(transitions.map (t) -> t.name).join "|"})/i"
      if shouldTransitionRegex.test(message)
        [ __, toState] =  message.match shouldTransitionRegex

    fetch("#{jiraUrl}/rest/api/2/user/search?username=#{msg.message.user.email_address}")
    .then (user) ->
      reporter = user[0] if user and user.length is 1
      quoteRegex = /`{1,3}([^]*?)`{1,3}/
      labelsRegex = /\s+#\S+/g
      priorityRegex = eval "/\\s+!(#{(priorities.map (priority) -> priority.name).join '|'})\\b/i" if priorities
      mentionRegex = eval "/(?:@([\\w._]*))/i"

      labels = []

      desc = message.match(quoteRegex)[1] if quoteRegex.test(message)
      message = message.replace(quoteRegex, "") if desc
      message = message.replace(shouldTransitionRegex, "") if toState

      if labelsRegex.test message
        labels = (message.match(labelsRegex).map((label) -> label.replace('#', '').trim())).concat(labels)
        message = message.replace labelsRegex, ""

      if priorities and priorityRegex.test message
        priority = message.match(priorityRegex)[1]
        priority = priorities.find (p) -> p.name.toLowerCase() is priority.toLowerCase()
        message = message.replace priorityRegex, ""

      if mentionRegex.test message
        assignee = message.match(mentionRegex)[1]
        message = message.replace mentionRegex, ""

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
        method: "POST"
        body: JSON.stringify issue
    .then (json) ->
      issue = json.key
      send msg, "Ticket created: #{jiraUrl}/browse/#{issue}"

      if toState
        msg.match = [ message, issue, toState ]
        handleTransitionRequest msg

      if assignee
        msg.match = [ message, issue, assignee ]
        handleAssignRequest msg
    .catch (error) ->
      send msg, "Unable to create ticket #{error}"

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
      fetch("#{jiraUrl}/rest/api/2/issue/#{ticket}")
      .then (json) ->
        id = json.id
        message = """
          *<#{jiraUrl}/browse/#{ticket}|#{json.key}> - #{json.fields.summary.trim()}*
          Status: #{json.fields.status.name}
          Assignee: #{lookupUserWithJira json.fields.assignee}
          Reporter: #{lookupUserWithJira json.fields.reporter}
        """
      .then (json) ->
        fetch "#{jiraUrl}/rest/api/2/issue/#{ticket}/watchers"
      .then (json) ->
        if json.watchCount > 0
          watchers = []
          watchers.push lookupUserWithJira watcher for watcher in json.watchers
          message += "\nWatchers: #{watchers.join ', '}"
      .then (json) ->
        fetch "#{jiraUrl}/rest/dev-status/1.0/issue/detail?issueId=#{id}&applicationType=github&dataType=branch"
      .then (json) ->
        if json.detail?[0]?.pullRequests
          return Promise.all json.detail[0].pullRequests.map (pr) ->
            if pr.status is "OPEN"
              orgAndRepo = pr.destination.url.split("github.com")[1].split('tree')[0].split('/')
              repo = octo.repos(orgAndRepo[1], orgAndRepo[2])
              return repo.pulls(pr.id.replace('#', '')).fetch()
      .then (prs) ->
        return Promise.all prs.map (pr) ->
          return if not pr
          author = lookupUserWithGithub pr.user
          assignee = lookupUserWithGithub pr.assignee
          return Promise.all [ pr, author, assignee ]
      .then (prs) ->
        for p in prs when p
          pr = p[0]
          author = p[1]
          assignee = p[2]
          message += """\n
            *<#{pr.htmlUrl}|#{pr.title}>* +#{pr.additions} -#{pr.deletions}
            Updated: *#{moment(pr.updatedAt).fromNow()}*
            Status: #{if pr.mergeable then "Mergeable" else "Unresolved Conflicts"}
            Author: #{if author then "<@#{author.id}>" else "Unknown"}
            Assignee: #{if assignee then "<@#{assignee.id}>" else "Unassigned"}
          """
        return message
    ).then (messages) ->
      send msg, message, no for message in messages
    .catch (error) ->
      send msg, message, no for message in messages
      send msg, "*Error:* #{error}"

  handleTransitionRequest = (msg) ->
    msg.finish()
    [ __, ticket, toState ] = msg.match
    ticket = ticket.toUpperCase()

    fetch("#{jiraUrl}/rest/api/2/issue/#{ticket}?expand=transitions.fields")
    .then (json) ->
      type = _(transitions).find (type) -> type.name is toState
      transition = json.transitions.find (state) -> state.to.name.toLowerCase() is type.jira.toLowerCase()
      if transition
        send msg, "Transitioning `#{ticket}` to `#{transition.to.name}`"
        fetch "#{jiraUrl}/rest/api/2/issue/#{ticket}/transitions",
          method: "POST"
          body: JSON.stringify
            transition:
              id: transition.id
      else
        send msg, "#{ticket} is a `#{json.fields.issuetype.name}` and does not support transitioning from `#{json.fields.status.name}` to `#{type.jira}` :middle_finger:"
    .catch (error) ->
      send msg, "An error has occured: #{error}"

  handleRankRequest = (msg) ->
    msg.finish()
    [ __, ticket, direction ] = msg.match
    ticket = ticket.toUpperCase()
    direction = direction.toLowerCase()

    switch direction
      when "up", "top" then direction = "Top"
      when "down", "bottom" then direction = "Bottom"
      else throw "invalid direction"

    fetch("#{jiraUrl}/rest/api/2/issue/#{ticket}")
    .then (json) ->
      if json.id
        fetch "#{jiraUrl}/secure/Rank#{direction}.jspa?issueId=#{json.id}"
        #Note: this fetch returns HTML and cannot be validated/parsed for success
      else
        throw "Cannot find ticket `#{ticket}`"
    .then () ->
      send msg, "Ranked `#{ticket}` to `#{direction}`"
    .catch (error) ->
      send msg, "An error has occured: #{error}"

  handleAssignRequest = (msg) ->
    msg.finish()
    [ __, ticket, person ] = msg.match
    person = if person is "me" then msg.message.user.name else person
    ticket = ticket.toUpperCase()
    slackUser = lookupSlackUser person

    if slackUser
      fetch("#{jiraUrl}/rest/api/2/user/search?username=#{slackUser.email_address}")
      .then (user) ->
        jiraUser = user[0] if user and user.length is 1
        if jiraUser
          fetch "#{jiraUrl}/rest/api/2/issue/#{ticket}",
            method: "PUT"
            body: JSON.stringify
              fields:
                assignee:
                  name: jiraUser.name
        else
          send msg, "Cannot find jira user <@#{slackUser.id}>"
      .then () ->
        send msg, "Assigned <@#{slackUser.id}> to `#{ticket}`: #{jiraUrl}/browse/#{ticket}"
      .catch (error) ->
        send msg, "Error: `#{error}`"
    else
      send msg, "Cannot find slack user `#{person}`"

  addComment = (msg) ->
    msg.finish()
    [ __, ticket, comment ] = msg.match

    fetch "#{jiraUrl}/rest/api/2/issue/#{ticket}/comment",
      method: "POST"
      body: JSON.stringify
        body:"""
          #{comment}

          Comment left by #{msg.message.user.name} in ##{msg.message.room} on #{robot.adapterName}
          https://#{robot.adapter.client.team.domain}.slack.com/archives/#{msg.message.room}/p#{msg.message.id.replace '.', ''}
        """
    .then () ->
      send msg, "Added comment to `#{ticket}`: #{jiraUrl}/browse/#{ticket}"
    .catch (error) ->
      send msg, "Error: `#{error}`"

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

  robot.respond /(?:help jira|jira help)(?: (.*))?/, (msg) ->
    [ __, topic] = msg.match

    overview = """
    *The Definitive #{robot.name.toUpperCase()} JIRA Manual*
    <@#{robot.adapter.self.id}> can help you *open* JIRA tickets, *transition* them thru
    different states, *comment* on them, *rank* them _up_ or _down_ or change
    who is *assigned* to a ticket
    """

    opening = """
    *Opening Tickets*
    > #{robot.name} `<type>` `<title>` [`<description>`]

    Where `<type>` is one of the following: #{(_(types).keys().map (t) -> "`#{t}`").join ',  '}
    `<description>` is optional and is surrounded with single or triple backticks
    and can be used to provide a more detailed description for the ticket.
    `<title>` is a short summary of the ticket
        *Optional `<title>` Attributes*
            _Labels_: include one or many hashtags that will become labels on the jira ticket
                 `#quick #techdebt`

            _Assignment_: include a handle that will be used to assign the ticket after creation
                 `@username`

            _Transitions_: include a transition to make after the ticket is created
                #{(transitions.map (t) -> "`>#{t.name}`").join ',  '}

            _Priority_: include the ticket priority to be assigned upon ticket creation
                #{(_(priorities).map (p) -> "`!#{p.name.toLowerCase()}`").join ',  '}
    """

    rank = """
    *Ranking Tickets*
    > `<ticket>` rank top
    > `<ticket>` rank bottom

    Where `<ticket>` is the JIRA ticket number. Note this will rank it the top
    of column for the current state
    """

    comment = """
    *Commenting on a Ticket*
    > `<ticket>` < `<comment>`

    Where `<ticket>` is the JIRA ticket number
    and `<comment>` is the comment you wish to leave on the ticket
    """

    assignment = """
    *Assigning Tickets*
    > `<ticket>` assign `@username`

    Where `<ticket>` is the JIRA ticket number
    and `@username` is a user handle
    """

    transition = """
    *Transitioning Tickets*
    > `<ticket>` to `<state>`
    > `<ticket>` >`<state>`

    Where `<ticket>` is the JIRA ticket number
    and `<state>` is one of the following: #{(transitions.map (t) -> "`#{t.name}`").join ',  '}
    """

    if _(["report", "open", "file", commands.split '|']).chain().flatten().contains(topic).value()
      responses = [ opening ]
    else if _(["rank", "ranking"]).contains topic
      responses = [ rank ]
    else if _(["comment", "comments"]).contains topic
      responses = [ comment ]
    else if _(["assign", "assignment"]).contains topic
      responses = [ assignment ]
    else if _(["transition", "transitions", "state", "move"]).contains topic
      responses = [ transition ]
    else
      responses = [ overview, opening, rank, comment, assignment, transition ]

    send msg, "\n#{responses.join '\n\n\n'}"
