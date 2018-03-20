# encoding: utf-8
require "sinatra"
require "json"
require "httparty"
require "redis"
require "dotenv"
require "text"
require "logger"


logger = Logger.new(STDOUT)

configure do
	# Load .env vars
	Dotenv.load

  # Set up redis
  case settings.environment
  when :development
    uri = URI.parse(URI.encode(ENV["LOCAL_REDIS_URL"]))
  when :production
    uri = URI.parse(URI.encode(ENV["REDISCLOUD_URL"]))
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

post "/" do
	begin
    logger.info("Message received: #{params}")
		puts "[LOG] #{params}"
		params[:text] = params[:text].sub(params[:trigger_word], "").strip
		if params[:token] != ENV["OUTGOING_WEBHOOK_TOKEN"]
      response = "Invalid token"
    elsif params[:text].match(/^set blocker/i)
    	response = set_blocker(params)
    elsif params[:text].match(/^resolve/i) 
    	response = resolve_block
    elsif params[:text].match(/^ping blocker/i) 
    	response = ping_blocker
    elsif params[:text].match(/^help$/i)
      response = respond_with_help
    else 
    	response = invalid_request
    end	
  rescue => e
    puts "[ERROR] #{e}"
    response = ""
  end
  logger.info("Response sent: #{response}")  
	status 200
	body json_response_for_slack(response)
end

# Puts together the json payload that needs to be sent back to Slack
def json_response_for_slack(reply)
  response = { text: reply, link_names: 1 }
  logger.info("JSON response is #{response.to_json}")
  response[:username] = ENV["BOT_USERNAME"] unless ENV["BOT_USERNAME"].nil?
  response[:icon_emoji] = ENV["BOT_ICON"] unless ENV["BOT_ICON"].nil?
  response.to_json
end

# Set a new blocker
def set_blocker(params)
  logger.info("blocker params: #{params}")
	channel_id = params[:channel_id]
	if existing_blocker
    logger.info("existing blocker #{existing_blocker}")
		time_blocked = get_time_blocked
		response = "Can not create new issue. Current issue has been blocked by #{existing_blocker} for #{time_blocked}"
	else
    params[:blocker] = params[:text].match(/<(.*?)>/)[1]
    logger.debug(params[:blocker])
		$redis.set("blocked", params[:user_name])
		$redis.set("time_blocked", Time.now.to_i)
		$redis.set("blocker", params[:blocker])
		$redis.set("team", params[:team_id])
		logger.debug("Block created for team #{params[:team_id]}!")
    response = "Block created for team #{params[:team_id]}!"
  end
  response
end

# Gets the existing blocker from redis
def resolve_block()
  blocker = $redis.get("blocker")
  blocked = $redis.get("blocked")
  response = "#{blocker} resolved #{blocked}'s issue after #{time_blocked}"
  time_blocked = $redis.get("time_blocked")
  $redis.set("blocker", nil)
  $redis.set("blocked", nil)
  $redis.set("time_blocked", nil)
  response
end

# Return time blocked
def ping_blocker()
	if existing_blocker
		blocker = $redis.get("blocker")
		blocked = $redis.get("blocked")
		time_blocked = get_time_blocked
    logger.info("Pinging blocker")
		response = "#{blocker} has been blocking #{blocked} for #{time_blocked}"
	else
    logger.info("No existing blocker")
	 response = "No existing blocks. Yay!"	
  end
  response
end

# Gets the existing blocker from redis
def existing_blocker()
  if $redis.get("blocker") === ("" || nil)
  	false
  else
  logger.info("Blocker exists: #{$redis.get('blocker').to_json}")
  $redis.get("blocker")
  end
end

# Return total time on current block
def get_time_blocked()
  logger.info("Getting time blocked")
	time_blocked = $redis.get("time_blocked").to_i
	now = Time.now.to_i

  total_time_blocked = Time.at(now - time_blocked).strftime("%H:%M:%S")

  response = "#{total_time_blocked}"
  response
end

# TODO: Check Slack channel for matching name
def is_valid_blocker(blocker_name)
	$redis.get(blocker_name)
end	

# Shows the help text.
def respond_with_help
  reply = <<help
Type `#{ENV["BOT_USERNAME"]} set blocker [@slack_user]` to set a block.
Type `#{ENV["BOT_USERNAME"]} resolve` to resolve an existing block.
Type `#{ENV["BOT_USERNAME"]} ping blocker` to ping the blocker and display time blocked.
help
  reply
end
