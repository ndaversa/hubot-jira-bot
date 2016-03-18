moment = require "moment"

Utils = require "../utils"

class PullRequest
  constructor: (json) ->
    @[k] = v for k,v of json

  toAttachment: ->
    self = @
    Utils.lookupUserWithGithub(@assignee)
    .then (assignee) ->
      color: "#ff9933"
      author_name: self.user.login
      author_icon: self.user.avatarUrl
      author_link: self.user.htmlUrl
      title: self.title
      title_link: self.htmlUrl
      fields: [
        title: "Updated"
        value: moment(self.updatedAt).fromNow()
        short: yes
      ,
        title: "Status"
        value: if self.mergeable then "Mergeable" else "Unresolved Conflicts"
        short: yes
      ,
        title: "Assignee"
        value: if assignee then "<@#{assignee.id}>" else "Unassigned"
        short: yes
      ,
        title: "Lines"
        value: "+#{self.additions} -#{self.deletions}"
        short: yes
      ]
      fallback: """
        *#{self.title}* +#{self.additions} -#{self.deletions}
        Updated: *#{moment(self.updatedAt).fromNow()}*
        Status: #{if self.mergeable then "Mergeable" else "Unresolved Conflicts"}
        Author: #{self.user.login}
        Assignee: #{if assignee then "#{assignee.name}" else "Unassigned"}
      """

module.exports = PullRequest
