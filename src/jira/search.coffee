Config = require "../config"
Ticket = require "./ticket"
Utils = require "../utils"

class Search

  @withQueryForProject: (query, project, msg, max=5) ->
    labels = []
    if Config.labels.regex.test query
      labels = (query.match(Config.labels.regex).map((label) -> label.replace('#', '').trim())).concat(labels)
      query = query.replace Config.labels.regex, ""

    jql = if query.length > 0 then "text ~ '#{query}'" else ""
    noResults = "No results for #{query}"
    found = "Found <#{Config.jira.url}/secure/IssueNavigator.jspa?jqlQuery=__JQL__&runQuery=true|__xx__ issues> containing `#{query}`"

    if project
      jql += " and " if jql.length > 0
      jql += "project = '#{project}'"
      noResults += " in project `#{project}`"
      found += " in project `#{project}`"

    if labels.length > 0
      jql += " and " if jql.length > 0
      jql += "labels = '#{label}'" for label in labels
      noResults += " with labels `#{labels.join ', '}`"
      found += " with labels `#{labels.join ', '}`"

    found.replace "__JQL__", encodeURIComponent jql
    Utils.fetch "#{Config.jira.url}/rest/api/2/search",
      method: "POST"
      body: JSON.stringify
        jql: jql
        startAt: 0
        maxResults: max
        fields: Config.jira.fields
    .then (json) ->
      if json.issues.length > 0
        text = found.replace("__xx__", json.total).replace "__JQL__", encodeURIComponent jql
      else
        text = noResults

      text: text
      tickets: (new Ticket issue for issue in json.issues)

module.exports = Search
