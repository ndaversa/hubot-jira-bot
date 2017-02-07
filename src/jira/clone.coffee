_ = require "underscore"

Config = require "../config"
Create = require "./create"
Utils = require "../utils"

class Clone
  @fromTicketKeyToProject: (key, project, channel, context, emit=yes) ->
    original = null
    cloned = null
    Create.fromKey(key)
    .then (issue) ->
      original = issue
      Utils.fetch("#{Config.jira.url}/rest/api/2/project/#{project}")
      .then (json) ->
        issueTypes = _(json.issueTypes).reject (it) -> it.name is "Sub-task"
        issueType = Utils.fuzzyFind issue.fields.issuetype.name, issueTypes, ['name']
        issueType = issueTypes[0] unless issueType
        Promise.reject "Unable to find a suitable issue type in #{project} that matches with #{original.fields.issuetype.name}" unless issueType

        Create.fromJSON
          fields:
            project:
              key: project
            summary: original.fields.summary
            labels: original.fields.labels
            description: """
              #{original.fields.description}

              Cloned from #{key}
            """
            issuetype: name: issueType.name
    .then (json) ->
      Create.fromKey(json.key)
    .then (ticket) ->
      cloned = ticket
      room = Utils.JiraBot.adapter.getRoomName context
      Utils.fetch "#{Config.jira.url}/rest/api/2/issueLink",
        method: "POST"
        body: JSON.stringify
          type:
            name: "Cloners"
          inwardIssue:
            key: original.key
          outwardIssue:
            key: cloned.key
          comment:
            body: """
              Cloned by #{context.message.user.name} in ##{room} on #{context.robot.adapterName}
              #{Utils.JiraBot.adapter.getPermalink context}
            """
    .then ->
      if emit
        Utils.robot.emit "JiraTicketCreated", context, ticket: cloned
        Utils.robot.emit "JiraTicketCloned", cloned, channel, key, context if context.message.room isnt channel
    .catch (error) ->
      Utils.robot.emit "JiraTicketCloneFailed", error, key, context if emit

module.exports = Clone
