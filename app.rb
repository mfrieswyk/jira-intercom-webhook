require 'bundler'
Bundler.require
require 'logger'
require 'intercom'

INTERCOM_REGEX = /https:\/\/app.intercom.io\/a\/apps\/(?<app_id>\S*)\/inbox\/(\S*\/)?conversation(s)?\/(?<conversation_id>\d*)/
INTERCOM_CLIENT = Intercom::Client.new(token: ENV['INTERCOM_API_KEY'])
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

    # get issue info
    issue_title = json['issue']['fields']['summary']
    issue_key = json['issue']['key']
    issue_status = json['issue']['fields']['status']['name']
    issue_type = json['issue']['fields']['issuetype']['name']
    issue_url = jira_issue_url(issue_key)
    assignee = json['issue']['fields']['assignee'] ? json['issue']['fields']['assignee']['name'] : "Unassigned"
    description = json['issue']['fields']['description']
    comment = json['comment'] ? json['comment']['body'] : nil
    match_data = description.scan(INTERCOM_REGEX)

    # iterate through description and send note to intercom conversation
    $i = 0
    $num = match_data.length

    while $i < $num do
      convo_id = match_data[$i][1]

      #open conversation and add note
      logger.info("Linking Jira issue #{issue_key} to Intercom conversation #{convo_id}")
      conversation = INTERCOM_CLIENT.conversations.find(:id => convo_id)
      logger.info(conversation.to_hash.to_json)
      status = conversation.open
      logger.info(status)
      if status = false
        INTERCOM_CLIENT.conversations.open(id: convo_id, admin_id: ENV['INTERCOM_ADMIN_ID'])
      end
      INTERCOM_CLIENT.conversations.reply(id: convo_id, type: 'admin', admin_id: ENV['INTERCOM_ADMIN_ID'], message_type: 'note', body: "<a href='#{issue_url}' target='_blank'>#{issue_type} [#{issue_key}] #{issue_title} </a><br><b>Status:</b> #{issue_status}<br><b>Assigned to:</b> #{assignee}#{comment ? "<br><b>Comment:</b> #{comment}" : "" }")

      #increment loop
      $i += 1
    end
  end
end
