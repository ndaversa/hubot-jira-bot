# Description:
#  Quickly file JIRA issues with hubot
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
#   hubot bug - File a bug in JIRA corresponding to the project
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

    robot.hear /bug (.+)/i, (msg) ->
      room = msg.message.room
      user = msg.message.user.name
      text = msg.match[1]
      project = projects[room]
      return msg.reply "Bugs must be submitted in of the following project channels: " + _(projects).keys() if not project

      issue = JSON.stringify
        fields:
          project:
            key: project
          summary: text
          labels: ["triage"]
          description: "Reported by #{user} in ##{room} on #{robot.adapterName}"
          issuetype:
            name: "Bug"

      robot.http(jiraUrl + "/rest/api/2/issue")
        .header("Content-Type", "application/json")
        .auth(auth)
        .post(issue) (err, res, body) ->
          try
            if res.statusCode is 201 and res.statusMessage is "Created"
              json = JSON.parse body
              msg.reply "Issue created: #{jiraUrl}/browse/#{json.key}"
              console.log "statusCode:", res.statusCode, "statusMessage:", res.statusMessage, "err:", err, "body:", body
            else
              msg.reply "Unable to file issue please notify @ndaversa"
              console.log "statusCode:", res.statusCode, "statusMessage:", res.statusMessage, "err:", err, "body:", body
          catch error
            msg.reply "Unable to file issue: #{error}"
