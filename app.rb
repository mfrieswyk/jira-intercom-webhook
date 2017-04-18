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

# use Rack::Auth::Basic, "Restricted Area" do |username, password|
#   puts "i am authorizing"
#   username == ENV['APP_USERNAME'] and password == ENV['APP_PASSWORD']
# end

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
    match_data = description.scan(INTERCOM_REGEX)

    # iterate through description and send note to intercom conversation
    match_data.each do |data1|
      data1.each do |data2|
        convo_id = data2

        # get issue info
        issue_title = json['issue']['fields']['summary']
        issue_key = json['issue']['key']
        issue_status = json['issue']['fields']['status']['name']
        issue_type = json['issue']['fields']['issuetype']['name']
        issue_url = jira_issue_url(issue_key)
        assignee = json['issue']['fields']['assignee']

        # get convo
        convo_response = INTERCOM_CLIENT.get_conversation(convo_id)

        # check if convo already linked
        if convo_response.code == 200
          open_convo = INTERCOM_CLIENT.open_conversation(convo_id)
          open_convo.to_json
        end

        # Add link to convo
        logger.info("Linking issue #{issue_key} in Intercom... to Conversation #{convo_id}")
        result = INTERCOM_CLIENT.note_conversation(convo_id, "<a href='#{issue_url}' target='_blank'>#{issue_type} [#{issue_key}] #{issue_title} </a> <b>Status:</b> #{issue_status} <b>Assigned to:</b> #{assignee}")
        result.to_json
      end
    end
  end
end
