# Description:
#  Quickly file JIRA tickets with hubot
#
# Dependencies:
#   lodash
#
# Configuration:
#   HUBOT_JIRA_URL (format: "https://jira-domain.com:9090")
#   HUBOT_JIRA_USERNAME
#   HUBOT_JIRA_PASSWORD
#   HUBOT_JIRA_PROJECTS_MAP (format: {\"web\":\"WEB\",\"android\":\"AN\",\"ios\":\"IOS\",\"platform\":\"PLAT\"}
#
# Commands:
#   hubot bug - File a bug in JIRA corresponding to the project of the channel
#   hubot task - File a task in JIRA corresponding to the project of the channel
#
# Author:
#   ndaversa

_ = require "lodash"

module.exports = (robot) ->
  projects = JSON.parse process.env.HUBOT_JIRA_PROJECTS_MAP
  jiraUrl = process.env.HUBOT_JIRA_URL
  jiraUsername = process.env.HUBOT_JIRA_USERNAME
  jiraPassword = process.env.HUBOT_JIRA_PASSWORD

  if jiraUsername != undefined && jiraUsername.length > 0
    auth = "#{jiraUsername}:#{jiraPassword}"
    report = (project, type, msg) ->
      issue = JSON.stringify
        fields:
          project:
            key: project
          summary: msg.match[1]
          labels: ["triage"]
          description: "Reported by #{msg.message.user.name} in ##{msg.message.room} on #{robot.adapterName}"
          issuetype:
            name: type

      robot.http(jiraUrl + "/rest/api/2/issue")
        .header("Content-Type", "application/json")
        .auth(auth)
        .post(issue) (err, res, body) ->
          try
            if res.statusCode is 201
              json = JSON.parse body
              msg.reply "Ticket created: #{jiraUrl}/browse/#{json.key}"
            else
              msg.reply "Unable to create ticket please notify @ndaversa"
              console.log "statusCode:", res.statusCode, "err:", err, "body:", body
          catch error
            msg.reply "Unable to create ticket: #{error} please notify @ndaversa"
            console.log "statusCode:", res.statusCode, "error:", error, "err:", err, "body:", body

    robot.respond /bug (.+)/i, (msg) ->
      room = msg.message.room
      project = projects[room]
      return msg.reply "Bugs must be submitted in one of the following project channels: " + _(projects).keys() if not project
      report project, "Bug", msg

    robot.respond /task (.+)/i, (msg) ->
      room = msg.message.room
      project = projects[room]
      return msg.reply "Tasks must be submitted in one of the following project channels: " + _(projects).keys() if not project
      report project, "Task", msg
