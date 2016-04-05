Config = require "../config"
Ticket = require "./ticket"
Utils = require "../utils"

class Search

  @withQueryForProject: (query, project, msg) ->
    labels = []
    if Config.labels.regex.test query
      labels = (query.match(Config.labels.regex).map((label) -> label.replace('#', '').trim())).concat(labels)
      query = query.replace Config.labels.regex, ""

    jql = if query.length > 0 then "text ~ \"#{query}\"" else ""
    noResults = "No results for #{query}"
    found = "Found __xx__ issues containing `#{query}`"

    if project
      jql += " and " if jql.length > 0
      jql += "project = #{project}"
      noResults += " in project `#{project}`"
      found += " in project `#{project}`"

    if labels.length > 0
      jql += " and " if jql.length > 0
      jql += "labels = #{label}" for label in labels
      noResults += " with labels `#{labels.join ', '}`"
      found += " with labels `#{labels.join ', '}`"

    Utils.fetch "#{Config.jira.url}/rest/api/2/search",
      method: "POST"
      body: JSON.stringify
        jql: jql
        startAt: 0
        maxResults: 5
        fields: Config.jira.fields
    .then (json) ->
      text: if json.issues.length > 0 then found.replace "__xx__", json.total else noResults
      tickets: (new Ticket issue for issue in json.issues)

module.exports = Search
