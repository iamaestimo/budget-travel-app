class AmadeusHotelService
  # Step 1: Find hotels in a city/location (Hotel List API)
  HOTEL_LIST_URL = "https://test.api.amadeus.com/v1/reference-data/locations/hotels/by-city".freeze
  HOTEL_LIST_BY_GEO_URL = "https://test.api.amadeus.com/v1/reference-data/locations/hotels/by-geocode".freeze

  # Step 2: Find available prices (Hotel Search API)
  HOTEL_SEARCH_URL = "https://test.api.amadeus.com/v3/shopping/hotel-offers".freeze

  # Additional endpoint for getting offers for a specific hotel
  HOTEL_OFFERS_BY_HOTEL_URL = "https://test.api.amadeus.com/v3/shopping/hotel-offers/by-hotel".freeze

  # Step 3: Complete booking (Hotel Booking API) - future implementation
  HOTEL_BOOKING_URL = "https://test.api.amadeus.com/v1/booking/hotel-bookings".freeze

  MAX_HOTELS_PER_REQUEST = 25 # Amadeus limit

  def initialize(access_token = nil)
    @access_token = access_token || AmadeusAuthService.new.call
  end

  # Find hotels in a city
  def hotels_by_city(city_code, limit = 10)
    return [] unless @access_token && city_code.present?

    # Add input validation
    city_code = city_code.to_s.upcase

    query_params = {
      cityCode: city_code,
      radius: 20,
      radiusUnit: "KM",
      ratings: [ "1", "2", "3", "4", "5" ],
      hotelSource: "ALL"
    }

    headers = {
      "Authorization" => "Bearer #{@access_token}",
      "Accept" => "application/json",
      "Content-Type" => "application/json"
    }

    # Add debug logging
    Rails.logger.debug "Hotel List API Request - URL: #{HOTEL_LIST_URL}"
    Rails.logger.debug "Hotel List API Request - Params: #{query_params.inspect}"
    Rails.logger.debug "Hotel List API Request - Headers: #{headers.inspect}"

    begin
      response = HTTP.headers(headers).get(HOTEL_LIST_URL, params: query_params)

      Rails.logger.debug "Hotel List API Response - Status: #{response.status}"
      Rails.logger.debug "Hotel List API Response - Body: #{response.body}"

      if response.status.success?
        parse_hotel_list_response(response)
      else
        error_data = JSON.parse(response.body)
        Rails.logger.error "Hotel List API Error: #{error_data.inspect}"
        []
      end
    rescue => e
      Rails.logger.error "Hotel List API Error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      []
    end
  end

  def search_hotel_offers(params)
    return [] unless @access_token

    # Get list of hotel IDs
    hotel_ids = hotels_by_city(params[:city_code])&.map { |h| h[:id] }
    return [] if hotel_ids.blank?

    # Split hotel IDs into batches
    hotel_batches = hotel_ids.each_slice(MAX_HOTELS_PER_REQUEST).to_a
    all_offers = []

    hotel_batches.each do |batch_ids|
      query_params = build_hotel_search_params(params.merge(hotel_ids: batch_ids))
      headers = {
        "Authorization" => "Bearer #{@access_token}",
        "Accept" => "application/json"
      }

      Rails.logger.debug "Hotel Offers API Request - Batch Size: #{batch_ids.size}"
      Rails.logger.debug "Hotel Offers API Request - URL: #{HOTEL_SEARCH_URL}"
      Rails.logger.debug "Hotel Offers API Request - Params: #{query_params.inspect}"
      Rails.logger.debug "Hotel Offers API Request - Headers: #{headers.inspect}"

      begin
        response = HTTP.headers(headers).get(HOTEL_SEARCH_URL, params: query_params)

        Rails.logger.debug "Hotel Offers API Response - Status: #{response.status}"
        Rails.logger.debug "Hotel Offers API Response - Body: #{response.body}"

        if response.status.success?
          offers = parse_hotel_offers_response(response)
          all_offers.concat(offers) if offers.present?
        else
          Rails.logger.error "Hotel Offers API Error: #{response.body}"
        end
      rescue => e
        Rails.logger.error "Hotel Offers API Error: #{e.message}"
      end
    end

    all_offers
  end

  private

  def parse_hotel_list_response(response)
    data = JSON.parse(response.body)

    if data["data"]
      data["data"].map do |hotel|
        {
          id: hotel["hotelId"],
          name: hotel["name"],
          city_code: hotel["address"]["cityCode"],
          address: [
            hotel["address"]["lines"]&.join(", "),
            hotel["address"]["cityName"],
            hotel["address"]["countryCode"]
          ].compact.join(", "),
          latitude: hotel["geoCode"]["latitude"],
          longitude: hotel["geoCode"]["longitude"]
        }
      end
    else
      []
    end
  end

  # Get offers for a specific hotel
  def hotel_offers_by_hotel(hotel_id, params)
    return [] unless @access_token

    query_params = build_hotel_offers_params(hotel_id, params)
    headers = { "Authorization" => "Bearer #{@access_token}" }

    begin
      response = HTTP.headers(headers).get(HOTEL_OFFERS_BY_HOTEL_URL, params: query_params)

      if response.status.success?
        parse_hotel_offers_response(response)
      else
        Rails.logger.error "Hotel Offers by Hotel API Error: #{response.body}"
        []
      end
    rescue => e
      Rails.logger.error "Hotel Offers by Hotel API Error: #{e.message}"
      []
    end
  end

  # Get details for a specific offer
  def hotel_offer_details(offer_id)
    return nil unless @access_token

    headers = { "Authorization" => "Bearer #{@access_token}" }
    url = "#{HOTEL_SEARCH_URL}/#{offer_id}"  # Using the hotel search URL for offer details

    begin
      response = HTTP.headers(headers).get(url)

      if response.status.success?
        parse_hotel_offer_details_response(response)
      else
        Rails.logger.error "Hotel Offer Details API Error: #{response.body}"
        nil
      end
    rescue => e
      Rails.logger.error "Hotel Offer Details API Error: #{e.message}"
      nil
    end
  end

  # Book a hotel - Implementation for future use
  # def book_hotel(offer_id, guests, payments)
  #   return nil unless @access_token
  #
  #   headers = {
  #     "Authorization" => "Bearer #{@access_token}",
  #     "Content-Type" => "application/json"
  #   }
  #
  #   payload = {
  #     data: {
  #       offerId: offer_id,
  #       guests: guests,
  #       payments: payments
  #     }
  #   }
  #
  #   begin
  #     response = HTTP.headers(headers).post(HOTEL_BOOKING_URL, json: payload)
  #
  #     if response.status.success?
  #       JSON.parse(response.body)
  #     else
  #       Rails.logger.error "Hotel Booking API Error: #{response.body}"
  #       nil
  #     end
  #   rescue => e
  #     Rails.logger.error "Hotel Booking API Error: #{e.message}"
  #     nil
  #   end
  # end

  private

  def build_hotel_search_params(params)
    # Format check-in and check-out dates
    check_in_date = params[:check_in_date] || (Date.today + 7.days).strftime("%Y-%m-%d")
    check_out_date = params[:check_out_date] || (Date.today + 10.days).strftime("%Y-%m-%d")

    # Convert to Date objects to validate
    begin
      check_in = Date.parse(check_in_date)
      check_out = Date.parse(check_out_date)

      # Make sure dates are not in the past and check_out is after check_in
      check_in_date = Date.today.strftime("%Y-%m-%d") if check_in < Date.today
      check_out_date = (check_in + 1.day).strftime("%Y-%m-%d") if check_out <= check_in
    rescue
      # Default to a 3-night stay starting in 7 days if date parsing fails
      check_in_date = (Date.today + 7.days).strftime("%Y-%m-%d")
      check_out_date = (Date.today + 10.days).strftime("%Y-%m-%d")
    end

    query_params = {
      hotelIds: Array(params[:hotel_ids]).join(","),
      checkInDate: check_in_date,
      checkOutDate: check_out_date,
      currency: params[:currency].presence || "USD",
      adults: params[:adults].presence || 1,
      roomQuantity: params[:rooms].presence || 1,
      priceRange: params[:max_price].present? ? "0-#{params[:max_price]}" : nil,
      bestRateOnly: true,
      view: "FULL"
    }

    # Remove nil values
    query_params.compact
  end

  def build_hotel_offers_params(hotel_id, params)
    # Base on the same logic as build_hotel_search_params
    hotel_params = build_hotel_search_params(params)
    # Add the hotel ID
    hotel_params.merge(hotelIds: hotel_id)
  end

  def parse_hotel_list_response(response)
    data = JSON.parse(response.body)

    if data["data"]
      data["data"].map do |hotel|
        {
          id: hotel["hotelId"],
          name: hotel["name"],
          iata_code: hotel["iataCode"],
          latitude: hotel.dig("geoCode", "latitude"),
          longitude: hotel.dig("geoCode", "longitude"),
          address: format_address(hotel),
          distance: hotel.dig("distance", "value"),
          distance_unit: hotel.dig("distance", "unit"),
          last_update: hotel["lastUpdate"]
        }
      end
    else
      []
    end
  end

  def parse_hotel_offers_response(response)
    data = JSON.parse(response.body)

    if data["data"]
      data["data"].map do |offer_data|
        hotel = offer_data["hotel"]
        offers = offer_data["offers"] || []

        hotel_info = {
          id: hotel["hotelId"],
          name: hotel["name"],
          rating: hotel["rating"],
          city_code: hotel.dig("cityCode"),
          latitude: hotel.dig("latitude"),
          longitude: hotel.dig("longitude"),
          address: format_hotel_address(hotel),
          amenities: hotel.dig("amenities"),
          description: hotel.dig("description", "text"),
          media: process_hotel_media(hotel.dig("media")),
          offers: []
        }

        # Process each offer
        offers.each do |offer|
          offer_info = {
            id: offer["id"],
            room_type: offer.dig("room", "typeEstimated", "category"),
            room_description: offer.dig("room", "description", "text"),
            guests: {
              adults: offer.dig("guests", "adults"),
              children: offer.dig("guests", "children")
            },
            price: {
              total: offer.dig("price", "total"),
              currency: offer.dig("price", "currency"),
              base: offer.dig("price", "base"),
              taxes: process_taxes(offer.dig("price", "taxes")),
              variations: process_price_variations(offer.dig("price", "variations"))
            },
            policies: {
              guarantee: offer.dig("policies", "guarantee"),
              payment_type: offer.dig("policies", "paymentType"),
              cancellation: process_cancellation_policy(offer.dig("policies", "cancellations"))
            },
            board_type: offer.dig("boardType"),
            included_services: offer.dig("include"),
            available: offer["available"]
          }

          hotel_info[:offers] << offer_info
        end

        hotel_info
      end
    else
      []
    end
  end

  def parse_hotel_offer_details_response(response)
    data = JSON.parse(response.body)

    if data["data"]
      # Similar to the hotel offers parser but for a single offer
      offer_data = data["data"]
      hotel = offer_data["hotel"]
      offer = offer_data["offers"]&.first

      return nil unless hotel && offer

      {
        hotel: {
          id: hotel["hotelId"],
          name: hotel["name"],
          rating: hotel["rating"],
          city_code: hotel.dig("cityCode"),
          latitude: hotel.dig("latitude"),
          longitude: hotel.dig("longitude"),
          address: format_hotel_address(hotel),
          amenities: hotel.dig("amenities"),
          description: hotel.dig("description", "text"),
          media: process_hotel_media(hotel.dig("media"))
        },
        offer: {
          id: offer["id"],
          room_type: offer.dig("room", "typeEstimated", "category"),
          room_description: offer.dig("room", "description", "text"),
          guests: {
            adults: offer.dig("guests", "adults"),
            children: offer.dig("guests", "children")
          },
          price: {
            total: offer.dig("price", "total"),
            currency: offer.dig("price", "currency"),
            base: offer.dig("price", "base"),
            taxes: process_taxes(offer.dig("price", "taxes")),
            variations: process_price_variations(offer.dig("price", "variations"))
          },
          policies: {
            guarantee: offer.dig("policies", "guarantee"),
            payment_type: offer.dig("policies", "paymentType"),
            cancellation: process_cancellation_policy(offer.dig("policies", "cancellations"))
          },
          board_type: offer.dig("boardType"),
          included_services: offer.dig("include"),
          available: offer["available"]
        }
      }
    else
      nil
    end
  end

  def format_address(hotel)
    return "Address not available" unless hotel.dig("address")

    address_parts = []
    address_parts << hotel.dig("address", "lines")&.join(", ") if hotel.dig("address", "lines")&.any?
    address_parts << hotel.dig("address", "postalCode") if hotel.dig("address", "postalCode")
    address_parts << hotel.dig("address", "cityName") if hotel.dig("address", "cityName")
    address_parts << hotel.dig("address", "countryCode") if hotel.dig("address", "countryCode")

    address_parts.compact.join(", ")
  end

  def format_hotel_address(hotel)
    return "Address not available" unless hotel.dig("address")

    address_parts = []
    address_parts << hotel.dig("address", "lines")&.join(", ") if hotel.dig("address", "lines")&.any?
    address_parts << hotel.dig("address", "postalCode") if hotel.dig("address", "postalCode")
    address_parts << hotel.dig("address", "cityName") if hotel.dig("address", "cityName")
    address_parts << hotel.dig("address", "countryCode") if hotel.dig("address", "countryCode")

    address_parts.compact.join(", ")
  end

  def process_hotel_media(media)
    return [] unless media.is_a?(Array)

    media.map do |item|
      {
        category: item["category"],
        url: item.dig("uri"),
        description: item.dig("description", "text")
      }
    end
  end

  def process_taxes(taxes)
    return [] unless taxes.is_a?(Array)

    taxes.map do |tax|
      {
        amount: tax["amount"],
        currency: tax["currency"],
        code: tax["code"],
        included: tax["included"]
      }
    end
  end

  def process_price_variations(variations)
    return {} unless variations.is_a?(Hash) && variations["changes"].is_a?(Array)

    changes = variations["changes"].map do |change|
      {
        start_date: change["startDate"],
        end_date: change["endDate"],
        total: change.dig("total")
      }
    end

    { average: variations["average"], changes: changes }
  end

  def process_cancellation_policy(cancellations)
    return [] unless cancellations.is_a?(Array)

    cancellations.map do |cancellation|
      {
        type: cancellation["type"],
        amount: cancellation["amount"],
        currency: cancellation["currency"],
        deadline: cancellation["deadline"]
      }
    end
  end
end
