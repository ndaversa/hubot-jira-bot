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


###The Definitive hubot JIRA Manual
@hubot can help you *search* for JIRA tickets, *open*
them, *transition* them thru different states, *comment* on them, *rank*
them _up_ or _down_, start or stop *watching* them or change who is
*assigned* to a ticket


*Opening Tickets*
> hubot [`<project>`] `<type>` `<title>` [`<description>`]

You can omit `<project>` when using the command in the desired projects channel
Otherwise you can specify one of the following for `<project>`: `#web`,  `#android`,  `#ios`,  `#platform`
`<type>` is one of the following: `story`,  `bug`,  `task`
`<description>` is optional and is surrounded with single or triple backticks
and can be used to provide a more detailed description for the ticket.
`<title>` is a short summary of the ticket
   *Optional `<title>` Attributes*
       _Labels_: include one or many hashtags that will become labels on the jira ticket
            `#quick #techdebt`

       _Assignment_: include a handle that will be used to assign the ticket after creation
            `@username`

       _Transitions_: include a transition to make after the ticket is created
           `>triage`,  `>icebox`,  `>backlog`,  `>devready`,  `>inprogress`,  `>design`

       _Priority_: include the ticket priority to be assigned upon ticket creation
           `!blocker`,  `!critical`,  `!major`,  `!minor`,  `!trivial`


*Creating Sub-tasks*
> hubot subtask `<ticket>` `<summary>`

Where `<ticket>` is the parent JIRA ticket number
and `<summary>` is a short summary of the task


*Cloning Tickets*
>`<ticket>` clone to `<channel>`
> `<ticket>` > `<channel>`

Where `<ticket>` is the JIRA ticket number
and `<channel>` is one of the following: `#web`,  `#android`,  `#ios`,  `#platform`


*Ranking Tickets*
>`<ticket>` rank top
> `<ticket>` rank bottom

Where `<ticket>` is the JIRA ticket number. Note this will rank it the top
of column for the current state


*Commenting on a Ticket*
>`<ticket>` < `<comment>`

Where `<ticket>` is the JIRA ticket number
and `<comment>` is the comment you wish to leave on the ticket


*Adding labels to a Ticket*
>`<ticket>` < `#label1 #label2 #label3`

Where `<ticket>` is the JIRA ticket number


*Assigning Tickets*
>`<ticket>` assign `@username`

Where `<ticket>` is the JIRA ticket number
and `@username` is a user handle


*Transitioning Tickets*
>`<ticket>` to `<state>`
> `<ticket>` >`<state>`

Where `<ticket>` is the JIRA ticket number
and `<state>` is one of the following: `triage`,  `icebox`,  `backlog`,  `devready`,  `inprogress`,  `design`


*Watching Tickets*
>`<ticket>` watch [`@username]`]

Where `<ticket>` is the JIRA ticket number
`@username` is optional, if specified the corresponding JIRA user will become
the watcher on the ticket, if omitted the message author will become the watcher


*Ticket Notifications*

Whenever you begin watching a JIRA ticket you will be notified (via a direct
message from @hubot) whenever any of the following events occur:
     - a comment is left on the ticket
     - the ticket is in progress
     - the ticket is resolved
To enable or disable this feature you can send the following directly to hubot:

> jira disable notifications

or if you wish to re-enable

> jira enable notifications


*Searching Tickets*
> hubot jira search `<term>`
   *Optional `<term>` Attributes*
       _Labels_: include one or many hashtags that will become labels included in the search
            `#quick #techdebt`

Where `<term>` is some text contained in the ticket you are looking for##Documentation with Configuration examples from above
