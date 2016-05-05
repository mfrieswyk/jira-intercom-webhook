require 'httparty'

class IntercomApiClient
  include HTTParty
  base_uri 'https://api.intercom.io'

  attr_reader :default_params

  def initialize(username, password)
    @default_params = {
      :basic_auth => {
        :username => username,
        :password => password
      },
      :headers => {
        'Accept'       => 'application/json',
        'Content-Type' => 'application/json'
      }
    }
  end

  def get_conversation id, params={}
    params.merge!(default_params)
    self.class.get("/conversations/#{id}", params)
  end

  # add a private note to the conversation
  #
  def note_conversation id, note
    params = default_params.merge({
      body: {
        body: note,
        type: 'admin',
        # id of admin user to attribute note to
        admin_id: ENV['INTERCOM_ADMIN_ID'],
        message_type: 'note'
      }.to_json
    })
    self.class.post("/conversations/#{id}/reply", params)
  end

  # open an existing conversation
  #
  def open_conversation id
    params = default_params.merge({
      body: {
        type: 'admin',
        message_type: 'open',
        # id of admin user to attribute note to
        admin_id: ENV['INTERCOM_ADMIN_ID']
      }.to_json
    })
    self.class.post("/conversations/#{id}/reply", params)
  end
end
