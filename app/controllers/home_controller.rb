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

  # =========== Hotel Methods ===========

  def hotel_search
    # Display the hotel search form
  end

  def hotel_results
    # Fetch and display hotel search results
    access_token = AmadeusAuthService.new.call
    @hotels = access_token ? search_hotels(access_token) : []
    render :hotel_results
  end

  def hotel_details
    # Fetch and display details for a specific hotel
    access_token = AmadeusAuthService.new.call

    hotel_id = params[:hotel_id]
    offer_id = params[:offer_id]

    if offer_id.present?
      # Get details for a specific offer
      service = AmadeusHotelService.new(access_token)
      @hotel_offer = service.hotel_offer_details(offer_id)

      if @hotel_offer.nil?
        @error = "Could not find details for the selected offer."
      end
    elsif hotel_id.present?
      # Get all offers for a specific hotel
      service = AmadeusHotelService.new(access_token)
      search_params = extract_hotel_search_params
      @hotel_offers = service.hotel_offers_by_hotel(hotel_id, search_params)

      if @hotel_offers.empty?
        @error = "Could not find offers for the selected hotel."
      end
    else
      @error = "Hotel ID or Offer ID is required."
    end

    render :hotel_details
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
      adults: params[:adults].presence || 1,
      max: 5  # Limit results
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
        # Guard against nil segments
        segments = flight.dig("itineraries", 0, "segments") || []

        {
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

  # =========== Hotel Helper Methods ===========

  def search_hotels(access_token)
    service = AmadeusHotelService.new(access_token)
    search_params = extract_hotel_search_params

    if search_params[:city_code].present?
      # First get list of hotels in the city
      hotels = service.hotels_by_city(search_params[:city_code])

      if hotels.empty?
        @error = "No hotels found in the specified city."
        return []
      end

      # Extract hotel IDs and add them to search params
      search_params[:hotel_ids] = hotels.map { |h| h[:id] }.join(",")

      # Log the hotel IDs for debugging
      Rails.logger.debug "Hotel IDs for offers search: #{search_params[:hotel_ids]}"

      # Then get offers for these hotels
      results = service.search_hotel_offers(search_params)

      if results.empty?
        @error = "No hotel offers found matching your criteria."
      end

      results
    else
      @error = "Please provide a city code to search for hotels."
      []
    end
  rescue => e
    Rails.logger.error "Hotel search error: #{e.message}"
    @error = "An error occurred while searching for hotels."
    []
  end

  def extract_hotel_search_params
    {
      city_code: params[:city_code].presence,
      check_in_date: params[:check_in_date].presence,
      check_out_date: params[:check_out_date].presence,
      adults: params[:adults].presence,
      rooms: params[:rooms].presence,
      max_price: params[:max_price].presence,
      currency: params[:currency].presence || "USD",
      ratings: extract_hotel_ratings,
      amenities: extract_hotel_amenities
    }
  end

  def extract_hotel_ratings
    return nil unless params[:ratings].present?

    if params[:ratings].is_a?(Array)
      params[:ratings]
    elsif params[:ratings].is_a?(String) && params[:ratings].include?(",")
      params[:ratings].split(",")
    elsif params[:ratings].is_a?(String)
      [ params[:ratings] ]
    else
      nil
    end
  end

  def extract_hotel_amenities
    return nil unless params[:amenities].present?

    if params[:amenities].is_a?(Array)
      params[:amenities]
    elsif params[:amenities].is_a?(String) && params[:amenities].include?(",")
      params[:amenities].split(",")
    elsif params[:amenities].is_a?(String)
      [ params[:amenities] ]
    else
      nil
    end
  end
end
