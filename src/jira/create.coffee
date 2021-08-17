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

  @with: (project, type, summary, context, fields, emit=yes) ->
    toState = null
    assignee = null
    room = Utils.JiraBot.adapter.getRoomName context

    if context.message.user.email_address
      user = User.withEmail(context.message.user.email_address)
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
        Reported by #{context.message.user.name} in ##{room} on #{context.robot.adapterName}
        #{Utils.JiraBot.adapter.getPermalink context}
      """
      issue.fields.reporter = reporter if reporter
      issue.fields.priority = id: priority.id if priority
      Create.fromJSON issue
    .then (json) ->
      Create.fromKey(json.key)
      .then (ticket) ->
        Promise.all([
          Transition.forTicketToState ticket, toState, context, no, no if toState
          Assign.forTicketToPerson ticket, assignee, context, no, no if assignee
          ticket
        ])
        .catch (error) ->
          Utils.robot.logger.error error
          [ undefined, text:error, ticket]
      .then (results) ->
        [ transition, assignee, ticket ] = results
        roomProject = Config.maps.projects[room]
        if emit
          Utils.robot.emit "JiraTicketCreated", context,
            ticket: ticket
            transition: transition
            assignee: assignee
        unless emit and roomProject is project
          Utils.robot.emit "JiraTicketCreatedElsewhere", context,
            ticket: ticket
            transition: transition
            assignee: assignee
        ticket
      .catch (error) ->
        context.robot.logger.error error.stack
    .catch (error) ->
      Utils.robot.logger.error error.stack
      Utils.robot.emit "JiraTicketCreationFailed", error, context if emit
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

  @subtaskFromKeyWith: (key, summary, context, emit=yes) ->
    Create.fromKey(key)
    .then (parent) ->
      Create.with parent.fields.project.key, "Sub-task", summary, context,
        parent: key: parent.key
        labels: parent.fields.labels or []
        description: "Sub-task of #{key}\n\n"
      , emit

module.exports = Create
