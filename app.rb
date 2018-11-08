
# frozen_string_literal: true

require 'sinatra'
require 'json'
require 'httparty'
require 'redis'
require 'dotenv'
require 'text'
require 'logger'

logger = Logger.new(STDOUT)

configure do
  # Load .env vars
  Dotenv.load

  # Set up redis
  case settings.environment
  when :development
    uri = URI.parse(URI.encode(ENV['LOCAL_REDIS_URL']))
  when :production
    uri = URI.parse(URI.encode(ENV['REDISCLOUD_URL']))
  end
  $redis = Redis.new(host: uri.host, port: uri.port, password: uri.password)
end

# Handles the POST request made by the Slack Outgoing webhook
# Params sent in the request:
#
# token=abc123
# team_id=T0001
# channel_id=C123456
# channel_name=test
# timestamp=1355517523.000005
# user_id=U123456
# blocker=Steve
# text=blockbot set blocker @person
# trigger_word=blockbot
#

post '/' do
  begin
    puts "[LOG] #{params}"
    params[:text] = params[:text].sub(params[:trigger_word], '').strip
    response = if params[:token] != ENV['OUTGOING_WEBHOOK_TOKEN']
                 'Invalid token'
               elsif params[:text] =~ /^set blocker/i
                 create_a_block(params)
               elsif params[:text] =~ /^resolve/i
                 resolve_block
               elsif params[:text] =~ /^ping/i
                 ping_blocker
               elsif params[:text] =~ /^status/i
                 ping_blocker
               elsif params[:text] =~ /^help$/i
                 respond_with_help
               else
                 invalid_request
               end
  rescue StandardError => e
    puts "[ERROR] #{e}"
    response = ''
  end
  logger.info("Response sent: #{response}")
  status 200
  body json_response_for_slack(response)
end

# Puts together the json payload that needs to be sent back to Slack
def json_response_for_slack(reply)
  response = { text: reply, link_names: 1 }
  logger.info("JSON response is #{response.to_json}")
  response[:username] = ENV['BOT_USERNAME'] unless ENV['BOT_USERNAME'].nil?
  response[:icon_emoji] = ENV['BOT_ICON'] unless ENV['BOT_ICON'].nil?
  response.to_json
end

# Set block
def create_a_block(params)
  params[:blocker] = params[:text].match(/@(.*?)>/)[1]
  if existing_blocker
    time_blocked = get_time_blocked
    response = "Can not create new issue. Current issue has been blocked by <@#{existing_blocker}> for #{time_blocked}"
  else
    $redis.set('blocked', params[:user_id])
    $redis.set('blocker', params[:blocker])
    $redis.set('time_blocked', Time.now.to_i)
    response = "<@#{params[:user_id]}> is blocked by <@#{params[:blocker]}> in ##{params[:channel_name]}!"
  end
  response
end

# Gets the existing blocker from redis
def resolve_block
  blocker = $redis.get('blocker')
  blocked = $redis.get('blocked')
  if blocker != (nil || '') && blocked != (nil || '')
    response = "<@#{blocker}> resolved <@#{blocked}>'s issue after #{get_time_blocked}"
    create_or_update_time(blocked, 'total_time_blocked')
    create_or_update_time(blocker, 'total_time_blocking')
    $redis.set('blocker', nil)
    $redis.set('blocked', nil)
    $redis.set('time_blocked', nil)
  else
    response = 'No blocks found.Yay!'
  end 
  response
end

# Return time blocked
def ping_blocker
  if existing_blocker
    blocker = $redis.get('blocker')
    blocked = $redis.get('blocked')
    time_blocked = get_time_blocked
    logger.info('Pinging blocker')
    response = "<@#{blocker}> has been blocking <@#{blocked}> for #{time_blocked}"
  else
    response = 'No existing blocks. Yay!'
  end
  response
end

# Gets the existing blocker from redis
def existing_blocker
  if $redis.get('blocker') === ('' || nil)
    false
  else
    logger.info("Blocker exists: #{$redis.get('blocker').to_json}")
    $redis.get('blocker')
  end
end

# Return total time on current block
def get_time_blocked(in_seconds = false)
  logger.info('Getting time blocked')
  time_blocked = $redis.get('time_blocked').to_i
  now = Time.now.to_i

  total_time_blocked = Time.at(now - time_blocked)

  response = in_seconds ? total_time_blocked : total_time_blocked.strftime("%H:%M:%S")
  response
end

def create_or_update_time(user, time_column)
  last_time_block = get_time_blocked(true)
  if $redis.hmget("user:#{user}", time_column) === [nil]
    $redis.hmset("user:#{user}", time_column, last_time_block)
  else
    new_total_time = $redis.hmget("user:#{user}", column) + last_time_block
    $redis.hmset("user:#{user}", column, new_total_time)
  end
end

def invalid_request
  "Request invalid. Type `#{ENV['BOT_USERNAME']} help` for acceptable inputs"
end

# Shows the help text.
def respond_with_help
  reply = <<~help
    Type `#{ENV['BOT_USERNAME']} set blocker [@slack_user]` to set a block.
    Type `#{ENV['BOT_USERNAME']} resolve` to resolve an existing block.
    Type `#{ENV['BOT_USERNAME']} ping blocker` to ping the blocker and display time blocked.
    Type `#{ENV['BOT_USERNAME']} status` to check current block status.
help
  reply
end
