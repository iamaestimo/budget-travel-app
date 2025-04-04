class AmadeusAuthService
  AMADEUS_TOKEN_URL = "https://test.api.amadeus.com/v1/security/oauth2/token".freeze

  def initialize(client_id: Rails.application.credentials.dig(:amadeus, :client_id),
    client_secret: Rails.application.credentials.dig(:amadeus, :client_secret))
    @client_id = client_id
    @client_secret = client_secret
  end

  def call
    response = HTTP.auth(basic_auth_header)
                   .post(AMADEUS_TOKEN_URL, form: { grant_type: "client_credentials" })

    return response.parse["access_token"] if response.status.success?

    Rails.logger.error "Amadeus Auth Failed: #{response.status} - #{response.body}"
    nil
  rescue => e
    Rails.logger.error "Amadeus Auth Error: #{e.message}"
    nil
  end

  private

  def basic_auth_header
    "Basic #{Base64.strict_encode64("#{@client_id}:#{@client_secret}")}"
  end
end
