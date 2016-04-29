_ = require "underscore"

Config = require "./config"

class Help

  @forTopic: (topic, robot) ->
    overview = """
    *The Definitive #{robot.name.toUpperCase()} JIRA Manual*
    @#{robot.name} can help you *search* for JIRA tickets, *open*
    them, *transition* them thru different states, *comment* on them, *rank*
    them _up_ or _down_, start or stop *watching* them or change who is
    *assigned* to a ticket
    """

    opening = """
    *Opening Tickets*
    > #{robot.name} [`<project>`] `<type>` `<title>` [`<description>`]

    You can omit `<project>` when using the command in the desired projects channel
    Otherwise you can specify one of the following for `<project>`: #{(_(Config.maps.projects).keys().map (c) -> "`##{c}`").join ',  '}
    `<type>` is one of the following: #{(_(Config.maps.types).keys().map (t) -> "`#{t}`").join ',  '}
    `<description>` is optional and is surrounded with single or triple backticks
    and can be used to provide a more detailed description for the ticket.
    `<title>` is a short summary of the ticket
        *Optional `<title>` Attributes*
            _Labels_: include one or many hashtags that will become labels on the jira ticket
                 `#quick #techdebt`

            _Assignment_: include a handle that will be used to assign the ticket after creation
                 `@username`

            _Transitions_: include a transition to make after the ticket is created
                #{(Config.maps.transitions.map (t) -> "`>#{t.name}`").join ',  '}

            _Priority_: include the ticket priority to be assigned upon ticket creation
                #{(_(Config.maps.priorities).map (p) -> "`!#{p.name.toLowerCase()}`").join ',  '}
    """

    subtask = """
    *Creating Sub-tasks*
    > #{robot.name} subtask `<ticket>` `<summary>`

    Where `<ticket>` is the parent JIRA ticket number
    and `<summary>` is a short summary of the task
    """


    clone = """
    *Cloning Tickets*
    > `<ticket>` clone to `<channel>`
    > `<ticket>` > `<channel>`

    Where `<ticket>` is the JIRA ticket number
    and `<channel>` is one of the following: #{(_(Config.maps.projects).keys().map (c) -> "`##{c}`").join ',  '}
    """

    rank = """
    *Ranking Tickets*
    > `<ticket>` rank top
    > `<ticket>` rank bottom

    Where `<ticket>` is the JIRA ticket number. Note this will rank it the top
    of column for the current state
    """

    labels = """
    *Adding labels to a Ticket*
    > `<ticket>` < `#label1 #label2 #label3`

    Where `<ticket>` is the JIRA ticket number
    """


    comment = """
    *Commenting on a Ticket*
    > `<ticket>` < `<comment>`

    Where `<ticket>` is the JIRA ticket number
    and `<comment>` is the comment you wish to leave on the ticket
    """

    assignment = """
    *Assigning Tickets*
    > `<ticket>` assign `@username`

    Where `<ticket>` is the JIRA ticket number
    and `@username` is a user handle
    """

    transition = """
    *Transitioning Tickets*
    > `<ticket>` to `<state>`
    > `<ticket>` >`<state>`

    Where `<ticket>` is the JIRA ticket number
    and `<state>` is one of the following: #{(Config.maps.transitions.map (t) -> "`#{t.name}`").join ',  '}
    """

    watch = """
    *Watching Tickets*
    > `<ticket>` watch [`@username]`]

    Where `<ticket>` is the JIRA ticket number
    `@username` is optional, if specified the corresponding JIRA user will become
    the watcher on the ticket, if omitted the message author will become the watcher
    """

    notifications = """
    *Ticket Notifications*

    Whenever you begin watching a JIRA ticket you will be notified (via a direct
    message from @#{robot.name}) whenever any of the following events occur:
          - a comment is left on the ticket
          - the ticket is in progress
          - the ticket is resolved

    You will also be notified (without watching the ticket when):
         - you are mentioned on the ticket
         - you are assigned to the ticket

    To enable or disable this feature you can send the following directly to #{robot.name}:

    > jira disable notifications

    or if you wish to re-enable

    > jira enable notifications
    """

    search = """
    *Searching Tickets*
    > #{robot.name} jira search `<term>`
        *Optional `<term>` Attributes*
            _Labels_: include one or many hashtags that will become labels included in the search
                 `#quick #techdebt`

    Where `<term>` is some text contained in the ticket you are looking for
    """

    if _(["report", "open", "file", "subtask", _(Config.maps.types).keys()]).chain().flatten().contains(topic).value()
      responses = [ opening, subtask ]
    else if _(["clone", "duplicate", "copy"]).contains topic
      responses = [ clone ]
    else if _(["rank", "ranking"]).contains topic
      responses = [ rank ]
    else if _(["comment", "comments"]).contains topic
      responses = [ comment ]
    else if _(["labels", "label"]).contains topic
      responses = [ labels ]
    else if _(["assign", "assignment"]).contains topic
      responses = [ assignment ]
    else if _(["transition", "transitions", "state", "move"]).contains topic
      responses = [ transition ]
    else if _(["search", "searching"]).contains topic
      responses = [ search ]
    else if _(["watch", "watching", "notifications", "notify"]).contains topic
      responses = [ watch, notifications ]
    else
      responses = [ overview, opening, subtask, clone, rank, comment, labels, assignment, transition, watch, notifications, search ]

    return "\n#{responses.join '\n\n\n'}"

module.exports = Help
