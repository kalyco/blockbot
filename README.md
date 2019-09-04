# Blockbot

A blocker-awareness Slackbot for collaborative teams

![](https://i.pinimg.com/originals/2e/91/f2/2e91f2b632d8942c4096c66fd1b47783.jpg)

## Requirements

You'll need a [Slack](https://slack.com) account and a free [Heroku](https://www.heroku.com/) account to host the bot. You'll also need to be able to set up new integrations in Slack; if you're not able to do this, contact someone with admin access in your organization.

## Installation

1. Set up a Slack outgoing webhook at https://slack.com/services/new/outgoing-webhook. Make sure to pick a trigger word, such as `blockbot`. You might also want to set this up in a single room/team specific rooms

2. Grab the token for the outgoing webhook you just created, and a Slack API token, which you can get from https://api.slack.com/web.

3. Click this button to set up your Heroku app: [![Deploy](https://www.herokucdn.com/deploy/button.svg)](https://heroku.com/deploy)   
If you'd rather do it manually, then just clone this repo, set up a Heroku app with Redis Cloud (the free level is more than enough for this, set this up in Resources --> Add-ons), and deploy blockbot there. Make sure to set up the config variables in
[.env.example](https://github.com/gesteves/trebekbot/blob/master/.env.example) in your Heroku app's settings screen.

4. Point the outgoing webhook to https://[YOUR-HEROKU-APP].herokuapp.com

## Usage

* `blockbot set blocker [@slack_user]`: Instantiate a blocked state from a user.
* `blockbot ping blocker`: Ping the blocker and display the time blocked.
* `blockbot resolve`: Resolves an existing block.

## Credits & acknowledgements

Thanks to [Guillermo Esteves](https://github.com/gesteves) for building [trebekbot](https://github.com/gesteves/trebekbot), which was a great reference while building this.

## Contributing

Feel free to open a new issue if you have questions, concerns, bugs, or feature requests. This was originally an app built to alleviate bottlenecked communication at my company, but if it can potentially benefit other groups I would love to help optimize it.
