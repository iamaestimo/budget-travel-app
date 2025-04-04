class HomeController < ApplicationController
  def index
    access_token = AmadeusAuthService.new.call
    @flights = access_token ? search_flights(access_token) : []
  end

  private


  def search_flights(access_token)
    search_url = "https://test.api.amadeus.com/v2/shopping/flight-offers"
    headers = { "Authorization" => "Bearer #{access_token}" }

    future_date = (Date.today + 30.days).strftime("%Y-%m-%d")

    params = {
      originLocationCode: "ATL",      # Atlanta
      destinationLocationCode: "PAR", # Paris
      departureDate: future_date,
      adults: 1,
      maxPrice: 700,
      currencyCode: "USD"
    }

    response = HTTP.headers(headers).get(search_url, params: params)
    data = JSON.parse(response.body)

    if data["data"]
      data["data"].map do |flight|
        {
          price: flight.dig("price", "grandTotal") || "N/A",
          currency: flight.dig("price", "currency") || "USD",
          departure: flight.dig("itineraries", 0, "segments", 0, "departure", "iataCode"),
          arrival: flight.dig("itineraries", 0, "segments", 0, "arrival", "iataCode"),
          departure_time: flight.dig("itineraries", 0, "segments", 0, "departure", "at"),
          airline: flight.dig("itineraries", 0, "segments", 0, "carrierCode")
        }
      end
    else
      Rails.logger.error "API Error: #{data['errors']}"
      []
    end
  end
end
