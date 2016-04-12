# Hubot Jira Bot
Lets you search for JIRA tickets, open
them, transition them thru different states, comment on them, rank
them up or down, start or stop watching them or change who is
assigned to a ticket

###Dependencies:
- moment
- octokat
- node-fetch
- underscore
- fuse.js

###Configuration:
- `HUBOT_JIRA_URL` `https://jira-domain.com:9090`
- `HUBOT_JIRA_USERNAME`
- `HUBOT_JIRA_PASSWORD`
- `HUBOT_JIRA_TYPES_MAP`  `{"story":"Story / Feature","bug":"Bug","task":"Task"}`
- `HUBOT_JIRA_PROJECTS_MAP`  `{"web":"WEB","android":"AN","ios":"IOS","platform":"PLAT"}`
- `HUBOT_JIRA_TRANSITIONS_MAP` `[{"name":"triage","jira":"Triage"},{"name":"icebox","jira":"Icebox"},{"name":"backlog","jira":"Backlog"},{"name":"devready","jira":"Selected for Development"},{"name":"inprogress","jira":"In Progress"},{"name":"design","jira":"Design Triage"}]`
- `HUBOT_JIRA_PRIORITIES_MAP` `[{"name":"Blocker","id":"1"},{"name":"Critical","id":"2"},{"name":"Major","id":"3"},{"name":"Minor","id":"4"},{"name":"Trivial","id":"5"}]`
- `HUBOT_GITHUB_TOKEN` - Github Application Token
