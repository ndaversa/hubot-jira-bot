# Configuration:
#   HUBOT_GITHUB_ORG - Github Organization or Github User
#   HUBOT_GITHUB_TOKEN - Github Application Token
#   HUBOT_JIRA_GITHUB_DISABLED - Set to true if you wish to disable github integration
#   HUBOT_JIRA_PASSWORD
#   HUBOT_JIRA_DUPLICATE_DETECTION - Set to true if wish to detect duplicates when creating new issues
#   HUBOT_JIRA_PRIORITIES_MAP [{"name":"Blocker","id":"1"},{"name":"Critical","id":"2"},{"name":"Major","id":"3"},{"name":"Minor","id":"4"},{"name":"Trivial","id":"5"}]
#   HUBOT_JIRA_PROJECTS_MAP  {"web":"WEB","android":"AN","ios":"IOS","platform":"PLAT"}
#   HUBOT_JIRA_TRANSITIONS_MAP [{"name":"triage","jira":"Triage"},{"name":"icebox","jira":"Icebox"},{"name":"backlog","jira":"Backlog"},{"name":"devready","jira":"Selected for Development"},{"name":"inprogress","jira":"In Progress"},{"name":"design","jira":"Design Triage"}]
#   HUBOT_JIRA_TYPES_MAP  {"story":"Story / Feature","bug":"Bug","task":"Task"}
#   HUBOT_JIRA_URL (format: "https://jira-domain.com:9090")
#   HUBOT_JIRA_USERNAME
#   HUBOT_SLACK_BUTTONS {"watch":{"name":"watch","text":"Watch","type":"button","value":"watch","style":"primary"},"assign":{"name":"assign","text":"Assign to me","type":"button","value":"assign"},"devready":{"name":"devready","text":"Dev Ready","type":"button","value":"selected"},"inprogress":{"name":"inprogress","text":"In Progress","type":"button","value":"progress"},"rank":{"name":"rank","text":"Rank Top","type":"button","value":"top"},"running":{"name":"running","text":"Running","type":"button","value":"running"},"review":{"name":"review","text":"Review","type":"button","value":"review"},"resolved":{"name":"resolved","text":"Resolved","type":"button","style":"primary","value":"resolved"},"done":{"name":"done","text":"Done","type":"button","style":"primary","value":"done"}}
#   HUBOT_SLACK_PROJECT_BUTTON_STATE_MAP {"PLAT":{"inprogress":["review","running","resolved"],"review":["running","resolved"],"running":["resolved"],"resolved":["devready","inprogress"],"mention":["watch","assign","devready","inprogress","rank"]},"HAL":{"inprogress":["review","running","resolved"],"review":["running","resolved"],"running":["resolved"],"resolved":["devready","inprogress"],"mention":["watch","assign","devready","inprogress","rank"]},"default":{"inprogress":["review","done"],"review":["done"],"done":["devready, inprogress"],"mention":["watch","assign","devready","inprogress","rank"]}}
#   HUBOT_SLACK_VERIFICATION_TOKEN - The slack verification token for your application

class Config
  @cache:
    default: expiry: 60*1000 # 1 minute
    mention: expiry: 5*60*1000 # 5 minutes

  @duplicates:
    detection: !!process.env.HUBOT_JIRA_DUPLICATE_DETECTION and process.env.HUBOT_SLACK_BUTTONS
    timeout: 30*1000 # 30 seconds

  @maps:
    projects: JSON.parse process.env.HUBOT_JIRA_PROJECTS_MAP
    types: JSON.parse process.env.HUBOT_JIRA_TYPES_MAP
    priorities:
      if process.env.HUBOT_JIRA_PRIORITIES_MAP
        JSON.parse process.env.HUBOT_JIRA_PRIORITIES_MAP
    transitions:
      if process.env.HUBOT_JIRA_TRANSITIONS_MAP
        JSON.parse process.env.HUBOT_JIRA_TRANSITIONS_MAP

  @projects:
    prefixes: (key for team, key of Config.maps.projects).reduce (x,y) -> x + "-|" + y
    channels: (team for team, key of Config.maps.projects).reduce (x,y) -> x + "|" + y

  @types:
    commands: (command for command, type of Config.maps.types).reduce (x,y) -> x + "|" + y

  @jira:
      url: process.env.HUBOT_JIRA_URL
      username: process.env.HUBOT_JIRA_USERNAME
      password: process.env.HUBOT_JIRA_PASSWORD
      expand: "transitions"
      fields: ["issuetype", "status", "assignee", "reporter", "summary", "description", "labels", "project"]
      mentionRegex: /(?:\[~([\w._-]*)\])/i
      mentionRegexGlobal: /(?:\[~([\w._-]*)\])/gi
  @jira.urlRegexBase = "#{Config.jira.url}/browse/".replace /[-\/\\^$*+?.()|[\]{}]/g, '\\$&'
  @jira.urlRegex = new RegExp "(?:#{Config.jira.urlRegexBase})((?:#{Config.projects.prefixes}-)\\d+)\\s*", "i"
  @jira.urlRegexGlobal = new RegExp "(?:#{Config.jira.urlRegexBase})((?:#{Config.projects.prefixes}-)\\d+)\\s*", "gi"

  @github:
    disabled: !!process.env.HUBOT_JIRA_GITHUB_DISABLED
    organization: process.env.HUBOT_GITHUB_ORG
    token: process.env.HUBOT_GITHUB_TOKEN

  @slack:
    buttons:
      if process.env.HUBOT_SLACK_BUTTONS
        JSON.parse process.env.HUBOT_SLACK_BUTTONS
    project: button: state: map:
      if process.env.HUBOT_SLACK_PROJECT_BUTTON_STATE_MAP
        JSON.parse process.env.HUBOT_SLACK_PROJECT_BUTTON_STATE_MAP
    verification: token: process.env.HUBOT_SLACK_VERIFICATION_TOKEN
    token: process.env.HUBOT_SLACK_TOKEN
    api: token: process.env.HUBOT_SLACK_API_TOKEN or process.env.HUBOT_SLACK_TOKEN

  @ticket:
    regex: new RegExp "(^|\\s)(" + Config.projects.prefixes + "-)(\\d+)\\b", "i"
    regexGlobal: new RegExp "(^|\\s)(" + Config.projects.prefixes + "-)(\\d+)\\b", "gi"

  @commands:
    regex: new RegExp "(?:#?(#{Config.projects.channels})\\s+)?(#{Config.types.commands}) ([^]+)", "i"

  @transitions:
    if Config.maps.transitions
      regex: new RegExp "^((?:#{Config.projects.prefixes}-)(?:\\d+))\\s+(?:to\\s+|>\\s?)(#{(Config.maps.transitions.map (t) -> t.name).join "|"})", "i"
      shouldRegex: new RegExp "\\s+>\\s?(#{(Config.maps.transitions.map (t) -> t.name).join "|"})", "i"

  @priority:
    if Config.maps.priorities
      regex: new RegExp "\\s+!(#{(Config.maps.priorities.map (priority) -> priority.name).join '|'})\\b", "i"

  @quote:
    regex: /`{1,3}([^]*?)`{1,3}/

  @mention:
    regex: /(?:(?:^|\s+)@([\w._-]*))/i
    regexGlobal: /(?:(?:^|\s+)@([\w._-]*))/gi

  @rank:
    regex: new RegExp "(?:^|\\s)((?:#{Config.projects.prefixes}-)(?:\\d+)) rank (.*)", "i"

  @watch:
    notificationsRegex: /jira (allow|start|enable|disallow|disable|stop)( notifications)?/i
    regex: new RegExp "^((?:#{Config.projects.prefixes}-)(?:\\d+)) (un)?watch(?: @?([\\w._-]*))?", "i"

  @subtask:
    regex: new RegExp "subtask\\s+((?:#{Config.projects.prefixes}-)(?:\\d+)) ([^]+)", "i"

  @assign:
    regex: new RegExp "^((?:#{Config.projects.prefixes}-)(?:\\d+))(?: (un)?assign)? @?([\\w._-]*)\\s*$", "i"

  @clone:
    regex: new RegExp "^((?:#{Config.projects.prefixes}-)(?:\\d+))\\s*(?:(?:>|clone(?:s)?(?:\\s+to)?)\\s*)(?:#)?(#{Config.projects.channels})", "i"

  @comment:
    regex: new RegExp "^((?:#{Config.projects.prefixes}-)(?:\\d+))\\s?(?:<\\s?)([^]+)", "i"

  @labels:
    commandSplitRegex: new RegExp "(?:#{Config.projects.prefixes}-)(?:\\d+)\\s?(?:<|&lt;)([^]+)", "i"
    addRegex: new RegExp "^((?:#{Config.projects.prefixes}-)(?:\\d+))\\s?(?:<|&lt;)(?:(\\s*#\\S+)|(?:\\s*<#[A-Z0-9]*\\|(\\S+)>))+$", "i"
    slackChannelRegexGlobal: /(?:\s+|^)<#[A-Z0-9]*\|\S+>/g
    slackChannelRegex: /(?:\s+|^)<#[A-Z0-9]*\|(\S+)>/
    regex: /(?:\s+|^)#\S+/g

  @search:
    regex: /(?:j|jira) (?:s|search|find|query) (.+)/

  @help:
    regex: /(?:help jira|jira help)(?: (.*))?/

module.exports = Config
