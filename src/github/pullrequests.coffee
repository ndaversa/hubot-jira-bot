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

  @fromKey: (key) ->
    octo.search.issues.fetch
      q: "#{key} @#{Config.github.organization} state:open type:pr"
    .then (json) ->
      return Promise.all json.items.map (issue) ->
        octo.fromUrl(issue.pullRequest.url).fetch() if issue.pullRequest?.url
    .then (issues) ->
      new PullRequests _(issues).compact()

  toAttachment: ->
    attachments = (pr.toAttachment() for pr in @prs)
    Promise.all attachments

module.exports = PullRequests
