_ = require "underscore"
moment = require "moment"
Octokat = require "octokat"

Config = require "../config"
PullRequest = require "./pullrequest"
Utils = require "../utils"

octo = new Octokat token: Config.github.token

class PullRequests
  constructor: (prs) ->
    @prs = (new PullRequest p for p in prs)

  @fromId: (id) ->
    Utils.fetch("#{Config.jira.url}/rest/dev-status/1.0/issue/detail?issueId=#{id}&applicationType=github&dataType=branch")
    .then (json) ->
      if json.detail?[0]?.pullRequests
        return Promise.all json.detail[0].pullRequests.map (pr) ->
          if pr.status is "OPEN"
            orgAndRepo = pr.destination.url.split("github.com")[1].split('tree')[0].split('/')
            repo = octo.repos(orgAndRepo[1], orgAndRepo[2])
            return repo.pulls(pr.id.replace('#', '')).fetch()
    .then (prs) ->
      new PullRequests _(prs).compact()

  toAttachment: ->
    attachments = (pr.toAttachment() for pr in @prs)
    Promise.all attachments

module.exports = PullRequests
