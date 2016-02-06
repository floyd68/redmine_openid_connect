class OicSession < ActiveRecord::Base
  unloadable

  before_create :randomize_state!
  before_create :randomize_nonce!

  def self.plugin_config
    Setting.plugin_redmine_openid_connect
  end

  def plugin_config
    self.class.plugin_config
  end

  def host_name
    Setting.host_name
  end

  def openid_configuration_url
    plugin_config[:openid_connect_server_url] + '/.well-known/openid-configuration'
  end

  def get_dynamic_configuration
    HTTParty.get(openid_configuration_url)
  end

  def dynamic_configuration
    @dynamic_configuration ||= get_dynamic_configuration
  end

  def get_access_token!
    uri = dynamic_configuration['token_endpoint']

    response = HTTParty.post(
      uri,
      body: access_token_query,
      basic_auth: {username: plugin_config[:client_id], password: plugin_config[:client_secret] }
    )

    if response["error"].blank?
      self.access_token = response["access_token"] if response["access_token"].present?
      self.refresh_token = response["refresh_token"] if response["refresh_token"].present?
      self.id_token = response["id_token"] if response["id_token"].present?
      self.expires_at = (DateTime.now + response["expires_in"].seconds) if response["expires_in"].present?
      self.save!
    end
    return response
  end

  def self.parse_token(token)
    jwt = token.split('.')
    return JSON::parse(Base64::decode64(jwt[1]))
  end

  def claims
    if @claims.blank? || id_token_changed?
      @claims = self.class.parse_token(id_token)
    end
    return @claims
  end

  def get_user_info!
    uri = dynamic_configuration['userinfo_endpoint']

    response = HTTParty.get(
      uri,
      headers: { "Authorization" => "Bearer #{access_token}" }
    )

    if response.headers["content-type"] == 'application/jwt'
      # signed / encrypted response, extract before using
      return self.class.parse_token(response)
    else
      # unsigned response, just return the bare json
      return JSON::parse(response.body)
      decoded_token = response.body
    end
  end

  def is_authorized?
    unless plugin_config[:group].blank?
      # only run authorized code if group is specified
      return user["member_of"].present? && user["member_of"].include?(plugin_config[:group])
    end
    return true
  end

  def user
    if @user.blank? || id_token_changed?
      @user = JSON::parse(Base64::decode64(id_token.split('.')[1]))
    end
    return @user
  end

  def authorization_url
    config = dynamic_configuration
    authorization_query_string = authorization_query.map do |k,v|
      "#{k}=#{v}"
    end.join("&")
    config["authorization_endpoint"] + "?" + authorization_query_string
  end

  def end_session_url
    config = dynamic_configuration
    end_session_query_string = end_session_query.map do |k,v|
      "#{k}=#{v}"
    end.join("&")
    config["end_session_endpoint"] + "?" + end_session_query_string
  end

  def randomize_state!
    self.state = SecureRandom.uuid unless self.state.present?
  end

  def randomize_nonce!
    self.nonce = SecureRandom.uuid unless self.nonce.present?
  end

  def authorization_query
    query = {
      "response_type" => "code+id_token",
      "state" => self.state,
      "nonce" => self.nonce,
      "scope" => "openid+profile+email+user_name",
      "redirect_uri" => "#{host_name}/oic",
      "client_id" => plugin_config["client_id"],
    }
  end

  def access_token_query
    query = {
      'grant_type' => 'authorization_code',
      'code' => code,
      'scope' => 'openid+profile+email+user_name',
      'id_token' => id_token,
      'redirect_uri' => "#{host_name}/oic",
    }
  end

  def refresh_token_query
    query = {
      'grant_type' => 'refresh_token',
      'refresh_token' => refresh_token,
    }
  end

  def end_session_query
   query = {}
   query['id_token_hint'] = id_token
   query['session_state'] = session_state
   query['post_logout_redirect_uri'] = host_name

   query
  end
end