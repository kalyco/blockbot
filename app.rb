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
      params[:blocker] = params[:text].match(/<(.*?)>/)[1]
    	reponse =  set_blocker(params)
    elsif params[:text].match(/^resolve/i) 
    	reponse =  resolve_block
    elsif params[:text].match(/^ping blocker/i) 
    	reponse =  ping_blocker
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
		reponse = "Can not create new issue. Current issue has been blocked by #{existing_blocker} for #{time_blocked}"
	end	
	if is_valid_blocker(params[:blocker])
		$redis.set("blocked", params[:blocker])
		$redis.set("time_blocked", time.Now)
		$redis.set("blocker", params[:user_id])
		$redis.set("team", params[:team_id])
    logger.debug("Valid blocker")
		response = "Block created for team #{params[:team_id]}!"
	else
    reponse = "Invalid blocker"
    logger.debug("blocker is invalid")
  end
  reponse
end

# Gets the existing blocker from redis
def resolve_block()
  blocker = $redis.get("blocker")
  blocked = $redis.get("blocked")
  time_blocked = $redis.get("time_blocked")
  $redis.set("blocker", nil)
  $redis.set("blocked", nil)
  $redis.set("time_blocked", nil)
  response = "#{blocker} resolved #{blocked}'s issue after #{time_blocked}"
  response
end

# return time blocked
def ping_blocker()
	if existing_blocker
		blocker = $redis.get("blocker")
		blocked = $redis.get("blocked")
		time_blocked = get_time_blocked
    logger.info("Pinging blocker")
		reponse = "#{blocker} has been blocking #{blocked} for #{time_blocked}"
	else
    logger.info("No existing blocker")
	 response = "No existing blocks. Yay!"	
  end
  response
end

# Gets the existing blocker from redis
def existing_blocker()
  blocker = $redis.get("blocker")
  logger.info(blocker)
  if blocker === ("" || nil)
  	false
  end
  logger.info("Blocker exists: #{blocker.to_json}")
  blocker
end

# Return total time on current block
def get_time_blocked()
  logger.info("Getting time blocked")
	time_blocked = $redis.get("time_blocked")
	now = Time.now
  seconds_diff = (time_blocked.to_i - now.to_i).to_i.abs

  hours = seconds_diff / 3600
  seconds_diff -= hours * 3600

  minutes = seconds_diff / 60
  seconds_diff -= minutes * 60

  seconds = seconds_diff
  response = "#{hours.to_s.rjust(2, '0')}:#{minutes.to_s.rjust(2, '0')}:#{seconds.to_s.rjust(2, '0')}"
  response
end

def is_valid_blocker(blocker_name)
	valid = $redis.get(blocker_name)
  valid
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
