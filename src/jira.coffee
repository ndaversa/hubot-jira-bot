# Description:
#  Quickly file JIRA tickets with hubot
#  Also listens for mention of tickets and responds with information
#
# Dependencies:
#   None
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

module.exports = (robot) ->
  projects = JSON.parse process.env.HUBOT_JIRA_PROJECTS_MAP
  prefixes = (key for team, key of projects).reduce (x,y) -> x + "-|" + y
  jiraPattern = eval "/\\b(" + prefixes + "-)(\\d+)\\b/gi"

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
          description: """
                       Reported by #{msg.message.user.name} in ##{msg.message.room} on #{robot.adapterName}
                       https://#{robot.adapter.client.team.domain}.slack.com/archives/#{msg.message.room}/p#{msg.message.id.replace '.', ''}
                       """
          issuetype:
            name: type

      robot.http("#{jiraUrl}/rest/api/2/issue")
        .header("Content-Type", "application/json")
        .auth(auth)
        .post(issue) (err, res, body) ->
          try
            if res.statusCode is 201
              json = JSON.parse body
              msg.send "<@#{msg.message.user.id}> Ticket created: #{jiraUrl}/browse/#{json.key}"
            else
              msg.send "<@#{msg.message.user.id}> Unable to create ticket"
              console.log "statusCode:", res.statusCode, "err:", err, "body:", body
          catch error
            msg.send "<@#{msg.message.user.id}> Unable to create ticket: #{error}"
            console.log "statusCode:", res.statusCode, "error:", error, "err:", err, "body:", body

    robot.respond /bug (.+)/i, (msg) ->
      room = msg.message.room
      project = projects[room]
      return msg.reply "Bugs must be submitted in one of the following project channels:" + (" <\##{team}>" for team, key of projects) if not project
      report project, "Bug", msg

    robot.respond /task (.+)/i, (msg) ->
      room = msg.message.room
      project = projects[room]
      return msg.reply "Tasks must be submitted in one of the following project channels:" + (" <\##{team}>" for team, key of projects) if not project
      report project, "Task", msg

    robot.hear jiraPattern, (msg) ->
      for issue in msg.match
        robot.http("#{jiraUrl}/rest/api/2/issue/#{issue.toUpperCase()}")
          .auth(auth)
          .get() (err, res, body) ->
            try
              json = JSON.parse body
              message = """
                        *[#{json.key}] - #{json.fields.summary}*
                        Status: #{json.fields.status.name}
                        """

              if  json.fields.assignee and json.fields.assignee.displayName
                message += "\nAssignee: #{json.fields.assignee.displayName}\n"
              else
                message += "\nUnassigned\n"

              message += """
                         Reporter: #{json.fields.reporter.displayName}
                         JIRA: #{jiraUrl}/browse/#{json.key}\n
                         """

              robot.http("#{jiraUrl}/rest/dev-status/1.0/issue/detail?issueId=#{json.id}&applicationType=github&dataType=branch")
                .auth(auth)
                .get() (err, res, body) ->
                  try
                    json = JSON.parse body
                    if json.detail?[0]?.pullRequests
                      for pr in json.detail[0].pullRequests
                        message += "PR: #{pr.url}\n"
                  finally
                    msg.send message

            catch error
              try
               msg.send "*[Error]* #{json.errorMessages[0]}"
              catch busted
                msg.send "*[Error]* #{busted}"
