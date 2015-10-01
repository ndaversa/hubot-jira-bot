# Hubot Jira Bot
Quickly file JIRA tickets with hubot
Also listens for mention of tickets and responds with information

###Dependencies:
- moment
- octokat
- node-fetch

###Configuration:
-`HUBOT_JIRA_URL` `https://jira-domain.com:9090`
-`HUBOT_JIRA_USERNAME`
-`HUBOT_JIRA_PASSWORD`
-`HUBOT_JIRA_TYPES_MAP`  `\{\"story\":\"Story\ \/\ Feature\",\"bug\":\"Bug\",\"task\":\"Task\"\}`
-`HUBOT_JIRA_PROJECTS_MAP`  `\{\"web\":\"WEB\",\"android\":\"AN\",\"ios\":\"IOS\",\"platform\":\"PLAT\"\}`
-`HUBOT_GITHUB_TOKEN` - Github Application Token
