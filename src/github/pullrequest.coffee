moment = require "moment"

Utils = require "../utils"

class PullRequest
  constructor: (json) ->
    @[k] = v for k,v of json

  toAttachment: ->
    assignee = Utils.lookupUserWithGithub @assignee

    color: "#ff9933"
    author_name: @user.login
    author_icon: @user.avatarUrl
    author_link: @user.htmlUrl
    title: @title
    title_link: @htmlUrl
    fields: [
      title: "Updated"
      value: moment(@updatedAt).fromNow()
      short: yes
    ,
      title: "Status"
      value: if @mergeable then "Mergeable" else "Unresolved Conflicts"
      short: yes
    ,
      title: "Assignee"
      value: if assignee then "<@#{assignee.id}>" else "Unassigned"
      short: yes
    ,
      title: "Lines"
      value: "+#{@additions} -#{@deletions}"
      short: yes
    ]
    fallback: """
      *#{@title}* +#{@additions} -#{@deletions}
      Updated: *#{moment(@updatedAt).fromNow()}*
      Status: #{if @mergeable then "Mergeable" else "Unresolved Conflicts"}
      Author: #{@user.login}
      Assignee: #{if assignee then "#{assignee.name}" else "Unassigned"}
    """

module.exports = PullRequest
