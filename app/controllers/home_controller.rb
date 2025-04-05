class HomeController < ApplicationController
  def index
    access_token = AmadeusAuthService.new.call
    @flights = access_token ? search_flights(access_token) : []
  end

  def advanced_search; end

  def search_results
    access_token = AmadeusAuthService.new.call
    @flights = access_token ? advanced_search_flights(access_token) : []
    render :search_results
  end

  private

  def search_flights(access_token)
    search_url = "https://test.api.amadeus.com/v2/shopping/flight-offers"
    headers = { "Authorization" => "Bearer #{access_token}" }

    # Default to 30 days from today if no date provided or if date is in the past
    default_date = (Date.today + 30.days).strftime("%Y-%m-%d")
    selected_date = params[:departure_date].presence || default_date

    # Make sure the date is not in the past
    departure_date = Date.parse(selected_date) < Date.today ? default_date : selected_date

    query_params = {
      originLocationCode: params[:origin].presence || "SYD",
      destinationLocationCode: params[:destination].presence || "BKK",
      departureDate: departure_date,
      adults: params[:adults].presence || 1
    }

    # Add optional parameters if present
    query_params[:maxPrice] = params[:max_price] if params[:max_price].present?
    query_params[:currencyCode] = params[:currency] if params[:currency].present?

    begin
      response = HTTP.headers(headers).get(search_url, params: query_params)

      if response.status.success?
        process_response(response)
      else
        Rails.logger.error "API Error: #{response.body}"
        @error = "Failed to fetch flights. Please try again later."
        []
      end
    rescue HTTP::Error => e
      Rails.logger.error "HTTP Error: #{e.message}"
      @error = "Connection error occurred. Please try again later."
      []
    rescue StandardError => e
      Rails.logger.error "General Error: #{e.message}"
      @error = "An unexpected error occurred. Please try again later."
      []
    end
  end

  def advanced_search_flights(access_token)
    search_url = "https://test.api.amadeus.com/v2/shopping/flight-offers"
    headers = {
      "Authorization" => "Bearer #{access_token}",
      "Content-Type" => "application/json"
    }

    # Default to 30 days from today if no date provided or if date is in the past
    default_date = (Date.today + 30.days).strftime("%Y-%m-%d")
    selected_date = params[:departure_date].presence || default_date

    # Make sure the date is not in the past
    departure_date = Date.parse(selected_date) < Date.today ? default_date : selected_date

    # Format the time to include seconds
    departure_time = "#{params[:departure_time].presence || '10:00'}:00"

    # Build the request payload
    payload = {
      currencyCode: params[:currency].presence || "USD",
      originDestinations: [
        {
          id: "1",
          originLocationCode: params[:origin].presence || "SYD",
          destinationLocationCode: params[:destination].presence || "BKK",
          departureDateTimeRange: {
            date: departure_date,
            time: departure_time
          }
        }
      ],
      travelers: [],
      sources: [ "GDS" ],
      searchCriteria: {
        maxFlightOffers: params[:max_results].presence || 5,
        flightFilters: {
          cabinRestrictions: [
            {
              cabin: params[:cabin_class].presence || "ECONOMY",
              coverage: "MOST_SEGMENTS",
              originDestinationIds: [ "1" ]
            }
          ]
        }
      }
    }

    # Add travelers
    adults = params[:adults].to_i.positive? ? params[:adults].to_i : 1
    children = params[:children].to_i.positive? ? params[:children].to_i : 0
    infants = params[:infants].to_i.positive? ? params[:infants].to_i : 0

    # Add adult travelers
    adults.times do |i|
      payload[:travelers] << {
        id: (i + 1).to_s,
        travelerType: "ADULT"
      }
    end

    # Add child travelers
    children.times do |i|
      payload[:travelers] << {
        id: (adults + i + 1).to_s,
        travelerType: "CHILD"
      }
    end

    # Add infant travelers
    infants.times do |i|
      payload[:travelers] << {
        id: (adults + children + i + 1).to_s,
        travelerType: "INFANT"
      }
    end

    # Add flight filters if needed
    if params[:non_stop].present? && params[:non_stop] == "1"
      payload[:searchCriteria][:flightFilters][:connectionRestriction] = {
        maxNumberOfConnections: 0
      }
    end

    response = HTTP.headers(headers).post(search_url, json: payload)
    process_response(response)
  end

  def process_response(response)
    data = JSON.parse(response.body)

    if data["data"]
      data["data"].map do |flight|
        segments = flight.dig("itineraries", 0, "segments") || []

        {
          id: flight["id"],
          price: flight.dig("price", "grandTotal") || "N/A",
          currency: flight.dig("price", "currency") || "USD",
          departure: flight.dig("itineraries", 0, "segments", 0, "departure", "iataCode"),
          arrival: segments.empty? ? nil : segments.last.dig("arrival", "iataCode"),
          departure_time: flight.dig("itineraries", 0, "segments", 0, "departure", "at"),
          arrival_time: segments.empty? ? nil : segments.last.dig("arrival", "at"),
          airline: flight.dig("itineraries", 0, "segments", 0, "carrierCode"),
          flight_number: flight.dig("itineraries", 0, "segments", 0, "number"),
          duration: flight.dig("itineraries", 0, "duration"),
          stops: segments.length - 1,
          cabin_class: flight.dig("travelerPricings", 0, "fareDetailsBySegment", 0, "cabin"),
          aircraft: flight.dig("itineraries", 0, "segments", 0, "aircraft", "code"),
          segments: segments.map do |segment|
            {
              departure_airport: segment.dig("departure", "iataCode"),
              departure_terminal: segment.dig("departure", "terminal"),
              departure_time: segment.dig("departure", "at"),
              arrival_airport: segment.dig("arrival", "iataCode"),
              arrival_terminal: segment.dig("arrival", "terminal"),
              arrival_time: segment.dig("arrival", "at"),
              carrier: segment.dig("carrierCode"),
              flight_number: segment.dig("number"),
              aircraft: segment.dig("aircraft", "code"),
              duration: segment.dig("duration")
            }
          end
        }
      end
    else
      if data["errors"]
        Rails.logger.error "API Error: #{data['errors']}"
        @error = data["errors"].first&.dig("detail") || "An error occurred while fetching flights."
      else
        Rails.logger.error "Unknown API Error: #{data}"
        @error = "Unknown error occurred while fetching flights."
      end
      []
    end
  rescue => e
    Rails.logger.error "Flight Search Error: #{e.message}"
    @error = "Error: #{e.message}"
    []
  end
end
