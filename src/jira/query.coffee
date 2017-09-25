Config = require "../config"
Ticket = require "./ticket"
Utils = require "../utils"

class Query

  @withQuery: (jql, max=50) ->
    noResults = "No results for #{jql}"
    found = "Found <#{Config.jira.url}/secure/IssueNavigator.jspa?jqlQuery=__JQL__&runQuery=true|__xx__ issues>"
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

module.exports = Query
