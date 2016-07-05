_ = require "underscore"

Assign = require "./assign"
Config = require "../config"
Ticket = require "./ticket"
Transition = require "./transition"
User = require "./user"
Utils = require "../utils"

class Create
  @fromJSON: (json) ->
    Utils.fetch "#{Config.jira.url}/rest/api/2/issue",
      method: "POST"
      body: JSON.stringify json

  @with: (project, type, summary, msg, fields, emit=yes) ->
    if Config.maps.transitions
      if Config.transitions.shouldRegex.test(summary)
        [ __, toState] =  summary.match Config.transitions.shouldRegex
      summary = summary.replace(Config.transitions.shouldRegex, "") if toState

    if Config.mention.regex.test summary
      assignee = summary.match(Config.mention.regex)[1]
      summary = summary.replace Config.mention.regex, ""

    User.withEmail(msg.message.user.email_address)
    .then (reporter) ->
      labels = [ msg.message.room ]
      description = summary.match(Config.quote.regex)[1] if Config.quote.regex.test(summary)
      summary = summary.replace(Config.quote.regex, "") if description

      if Config.labels.regex.test summary
        labels = (summary.match(Config.labels.regex).map((label) -> label.replace('#', '').trim())).concat(labels)
        summary = summary.replace Config.labels.regex, ""

      if Config.maps.priorities and Config.priority.regex.test summary
        priority = summary.match(Config.priority.regex)[1]
        priority = Config.maps.priorities.find (p) -> p.name.toLowerCase() is priority.toLowerCase()
        summary = summary.replace Config.priority.regex, ""

      issue =
        fields:
          project: key: project
          summary: summary
          description: ""
          issuetype: name: type

      _(issue.fields).extend fields if fields
      issue.fields.labels = _(issue.fields.labels).union labels
      issue.fields.description += """
        #{(if description then description + "\n\n" else "")}
        Reported by #{msg.message.user.name} in ##{msg.message.room} on #{msg.robot.adapterName}
        #{Utils.JiraBot.adapter.getPermalink msg}
      """
      issue.fields.reporter = reporter if reporter
      issue.fields.priority = id: priority.id if priority
      Create.fromJSON issue
    .then (json) ->
      Create.fromKey(json.key)
      .then (ticket) ->
        Promise.all [
          Transition.forTicketToState ticket, toState, msg, no, no if toState
          Assign.forTicketToPerson ticket, assignee, msg, no, no if assignee
          ticket
        ]
      .then (results) ->
        [ transition, assignee, ticket ] = results
        roomProject = Config.maps.projects[msg.message.room]
        if emit
          Utils.robot.emit "JiraTicketCreated",
            ticket: ticket
            room: msg.message.room
            transition: transition
            assignee: assignee
        unless emit and roomProject is project
          Utils.robot.emit "JiraTicketCreatedElsewhere",
            ticket: ticket
            room: msg.message.room
            user: msg.message.user
            transition: transition
            assignee: assignee
        ticket
      .catch (error) ->
        msg.robot.logger.error error.stack
    .catch (error) ->
      Utils.robot.logger.error error.stack
      Utils.robot.emit "JiraTicketCreationFailed", error, msg.message.room if emit
      Promise.reject error

  @fromKey: (key) ->
    key = key.trim().toUpperCase()
    params =
      expand: Config.jira.expand
      fields: Config.jira.fields

    Utils.fetch("#{Config.jira.url}/rest/api/2/issue/#{key}#{Utils.buildQueryString params}")
    .then (json) ->
      Promise.all [
        json,
        Utils.fetch "#{Config.jira.url}/rest/api/2/issue/#{json.key}/watchers"
      ]
    .then (jsons) ->
      new Ticket _(jsons[0]).extend _(jsons[1]).pick("watchers")

  @subtaskFromKeyWith: (key, summary, msg, emit=yes) ->
    Create.fromKey(key)
    .then (parent) ->
      Create.with parent.fields.project.key, "Sub-task", summary, msg,
        parent: key: parent.key
        labels: parent.fields.labels or []
        description: "Sub-task of #{key}\n\n"
      , emit

module.exports = Create
