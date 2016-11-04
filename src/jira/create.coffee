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
    toState = null
    assignee = null
    room = Utils.JiraBot.adapter.getRoomName msg

    if msg.message.user.profile?.email?
      user = User.withEmail(msg.message.user.profile.email)
    else
      user = Promise.resolve()

    user.then (reporter) ->
      { summary, description, toState, assignee, labels, priority } = Utils.extract.all summary
      labels.unshift room

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
        Reported by #{msg.message.user.name} in ##{room} on #{msg.robot.adapterName}
        #{Utils.JiraBot.adapter.getPermalink msg}
      """
      issue.fields.reporter = reporter if reporter
      issue.fields.priority = id: priority.id if priority
      Create.fromJSON issue
    .then (json) ->
      Create.fromKey(json.key)
      .then (ticket) ->
        Promise.all([
          Transition.forTicketToState ticket, toState, msg, no, no if toState
          Assign.forTicketToPerson ticket, assignee, msg, no, no if assignee
          ticket
        ])
        .catch (error) ->
          Utils.robot.logger.error error
          [ undefined, text:error, ticket]
      .then (results) ->
        [ transition, assignee, ticket ] = results
        roomProject = Config.maps.projects[room]
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
