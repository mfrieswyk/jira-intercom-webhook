require 'bundler'
Bundler.require
require 'logger'
require './intercom_api_client.rb'

INTERCOM_REGEX = /https:\/\/app.intercom.io\/a\/apps\/(?<app_id>\S*)\/inbox\/(\S*\/)?conversation(s)?\/(?<conversation_id>\d*)/
INTERCOM_CLIENT = IntercomApiClient.new(ENV['INTERCOM_APP_ID'], ENV['INTERCOM_API_KEY'])
JIRA_HOSTNAME = ENV['JIRA_HOSTNAME']

configure :production do
  app_logger = Logger.new(STDOUT)
  set :logging, Logger::DEBUG
  use Rack::CommonLogger, app_logger
  set :dump_errors, true
  set :raise_errors, true
end

configure :development do
  app_logger = Logger.new(STDOUT)
  set :logging, Logger::DEBUG
  use Rack::CommonLogger, app_logger
end

configure :test do
  app_logger = Logger.new('/dev/null')
  set :logging, Logger::WARN
  use Rack::CommonLogger, app_logger
end

use Rack::Auth::Basic, "Restricted Area" do |username, password|
  puts "i am authorizing"
  username == 'matt' and password == 'matt'
end

#################
# helper methods
#
def jira_issue_url key
  %(https://#{JIRA_HOSTNAME}/browse/#{key})
end

def jira_issue_regex key
  /https:\/\/#{JIRA_HOSTNAME}\/browse\/#{key}/
end
#
#################

get '/health' do
  content_type :json
  {status: 'OK'}.to_json
end


post '/jira_to_intercom' do
  puts "here"
  logger.debug "In Jara to intercom def"
  content_type :json

  request.body.rewind

  begin
    data = request.body.read
    json = JSON.parse(data)
    if json.empty?
      logger.error('JSON payload is empty')
      halt 500
    end
  rescue JSON::ParserError => ex
    logger.error('Unable to parse JSON.')
    logger.error(ex)
    halt 500
  ensure
    logger.debug(data)
  end

  if ['jira:issue_created', 'jira:issue_updated'].include?(json['webhookEvent'])
    description = json['issue']['fields']['description']
    match_data = INTERCOM_REGEX.match(description)

    # check if description includes intercom conversation URL
    if match_data && match_data[:app_id] && match_data[:conversation_id]
      convo_id = match_data[:conversation_id]

      # get issue info
      issue_title = json['issue']['fields']['summary']
      issue_key = json['issue']['key']
      issue_url = jira_issue_url(issue_key)

      # get convo
      convo_response = INTERCOM_CLIENT.get_conversation(convo_id)

      # check if convo already linked
      if convo_response.code == 200
        issue_regex = jira_issue_regex(issue_key)
        convo_bodies = convo_response['conversation_parts']['conversation_parts'].map {|p| p['body'] }.compact.join
        # already linked, quit here
        if issue_regex.match(convo_bodies)
          logger.info("Issue #{issue_key} already linked in Intercom")
          halt 409
        end
      end

      # not linked, let's add a link
      logger.info("Linking issue #{issue_key} in Intercom...")
      result = INTERCOM_CLIENT.note_conversation(convo_id, "JIRA ticket: <a href='#{issue_url}' target='_blank'>#{issue_title} (#{issue_key})</a>")

      result.to_json
    end
  else
    logger.info("Unsupported JIRA webhook event")
    halt 400
  end
end
