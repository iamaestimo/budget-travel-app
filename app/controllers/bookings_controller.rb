class BookingsController < ApplicationController
  before_action :set_booking, only: [ :show, :edit, :update ]

  def new
    @booking = Booking.new
    @flight_id = params[:flight_id]

    # Get the flight details from the search
    if params[:flight_details].present?
      @flight_details = JSON.parse(params[:flight_details])

      # Get current pricing from Amadeus
      access_token = AmadeusAuthService.new.call
      if access_token
        current_price_data = get_current_flight_data(@flight_id, access_token)

        if current_price_data
          # Update flight details with current price
          @current_price = current_price_data[:price]
          @current_currency = current_price_data[:currency]

          # Check if price has changed
          @price_changed = @current_price.to_s != @flight_details["price"]

          # Add current price to flight details but keep original structure
          @flight_details["current_price"] = @current_price.to_s
          @flight_details["original_price"] = @flight_details["price"]
        else
          @error = "Unable to retrieve current pricing. Showing original price."
        end
      else
        @error = "Unable to connect to flight service. Showing original price."
      end
    else
      @error = "No flight details provided."
      redirect_to root_path
      nil
    end
  end

  def create
    @booking = Booking.new(booking_params)

    # Generate a random booking reference
    @booking.booking_reference = generate_booking_reference

    # Important: Make sure we have flight details from the form
    if params[:flight_details].present?
      # Store flight details in the booking
      @booking.flight_details = JSON.parse(params[:flight_details])

      if @booking.save
        # Make a POST request to Amadeus Flight Create Orders API
        booking_result = create_flight_booking(@booking)

        if booking_result
          redirect_to booking_path(@booking), notice: "Booking created successfully!"
        else
          alert = @booking.status == "price_changed" ?
            "Flight price has changed - please search again" :
            "Booking created but could not be confirmed with the airline"
          redirect_to booking_path(@booking), alert: alert
        end
      else
        # If booking save fails, go back to the form
        @flight_id = params[:booking][:flight_id]
        @flight_details = JSON.parse(params[:flight_details]) if params[:flight_details].present?
        render :new, status: :unprocessable_entity
      end
    else
      @flight_id = params[:booking][:flight_id]
      @error = "No flight details provided. Please try searching again."
      redirect_to root_path, alert: @error
    end
  end

  def show
    # You could add code here to refresh booking status from Amadeus if needed
  end

  def edit
    # Form to update passenger details, not the flight itself
  end

  def update
    if @booking.update(booking_params)
      # Make a PUT request to Amadeus to update the booking
      update_result = update_flight_booking(@booking)

      if update_result
        redirect_to booking_path(@booking), notice: "Booking updated successfully!"
      else
        redirect_to booking_path(@booking), alert: "Booking updated in our system but could not be updated with the airline."
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_booking
    @booking = Booking.find(params[:id])
  end

  def booking_params
    params.require(:booking).permit(
      :first_name, :last_name, :email, :flight_id,
      passenger_details: [ :title, :firstName, :lastName, :dateOfBirth ]
    )
  end

  def generate_booking_reference
    # Generate a unique booking reference code
    loop do
      reference = "BKG" + SecureRandom.alphanumeric(6).upcase
      break reference unless Booking.exists?(booking_reference: reference)
    end
  end

  def get_current_flight_data(flight_id, access_token)
    flight_url = "https://test.api.amadeus.com/v2/shopping/flight-offers"
    headers = {
      "Authorization" => "Bearer #{access_token}",
      "Content-Type" => "application/json"
    }

    response = HTTP.headers(headers).get(flight_url, params: { id: flight_id })
    return nil unless response.status.success?

    data = JSON.parse(response.body)
    flight_data = data.dig("data", 0)
    return nil unless flight_data

    {
      price: flight_data.dig("price", "total"),
      currency: flight_data.dig("price", "currency"),
      flight_data: flight_data
    }
  end

  def confirm_flight_price(flight_id, access_token)
    # Step 1: Get the flight offer with the correct format
    search_url = "https://test.api.amadeus.com/v2/shopping/flight-offers"
    headers = {
      "Authorization" => "Bearer #{access_token}",
      "Content-Type" => "application/json"
    }

    search_response = HTTP.headers(headers).get(search_url, params: { id: flight_id })

    unless search_response.status.success?
      Rails.logger.error "Failed to retrieve flight offer: #{search_response.body}"
      return nil
    end

    flight_offers_data = JSON.parse(search_response.body)
    flight_offer = flight_offers_data.dig("data", 0)

    unless flight_offer
      Rails.logger.error "No flight offer found with ID: #{flight_id}"
      return nil
    end

    # Step 2: Confirm the price using the pricing endpoint
    pricing_url = "https://test.api.amadeus.com/v1/shopping/flight-offers/pricing"
    pricing_headers = {
      "Authorization" => "Bearer #{access_token}",
      "Content-Type" => "application/json"
    }

    pricing_payload = {
      data: {
        type: "flight-offers-pricing",
        flightOffers: [ flight_offer ]
      }
    }

    begin
      pricing_response = HTTP.headers(pricing_headers).post(pricing_url, json: pricing_payload)

      unless pricing_response.status.success?
        Rails.logger.error "Failed to confirm flight price: #{pricing_response.body}"
        return nil
      end

      # Return the priced flight offer with confirmed pricing
      pricing_data = JSON.parse(pricing_response.body)
      priced_flight_offer = pricing_data.dig("data", "flightOffers", 0)

      priced_flight_offer
    rescue => e
      Rails.logger.error "Error during price confirmation: #{e.message}"
      nil
    end
  end

  def create_flight_booking(booking)
    # Ensure we have flight details before proceeding
    flight_data = booking.flight_details
    return false unless flight_data.present?

    access_token = AmadeusAuthService.new.call
    return false unless access_token

    # Instead of trying to fetch by ID, we'll reconstruct a proper flight search
    # based on the details we have in flight_data
    begin
      # Step 1: Search for flights with the same parameters
      search_url = "https://test.api.amadeus.com/v2/shopping/flight-offers"
      headers = {
        "Authorization" => "Bearer #{access_token}",
        "Content-Type" => "application/json"
      }

      # Extract search parameters from our flight_data
      origin = flight_data["departure"]
      destination = flight_data["arrival"]
      departure_date = DateTime.parse(flight_data["departure_time"]).strftime("%Y-%m-%d")

      # Make the search request
      query_params = {
        originLocationCode: origin,
        destinationLocationCode: destination,
        departureDate: departure_date,
        adults: 1,
        max: 10  # Fetch several options to increase the chance of finding a matching flight
      }

      Rails.logger.info "Searching flights with params: #{query_params.inspect}"
      search_response = HTTP.headers(headers).get(search_url, params: query_params)

      unless search_response.status.success?
        Rails.logger.error "Failed to search flights: #{search_response.body}"
        booking.update(status: "error", notes: "Failed to search for matching flights")
        return false
      end

      search_data = JSON.parse(search_response.body)
      flight_offers = search_data["data"]

      if flight_offers.empty?
        Rails.logger.error "No flight offers found for the search parameters"
        booking.update(status: "error", notes: "No matching flights found")
        return false
      end

      # Try to find a matching flight by comparing important details
      matching_flight = nil
      flight_offers.each do |offer|
        offer_price = offer.dig("price", "grandTotal").to_f
        original_price = flight_data["price"].to_f

        # Check price similarity (allow some difference)
        price_diff = (offer_price - original_price).abs
        next if price_diff > 100 # Skip if price difference is too large

        # Check if origin/destination match
        segments = offer.dig("itineraries", 0, "segments") || []
        next if segments.empty?

        offer_origin = segments.first.dig("departure", "iataCode")
        offer_destination = segments.last.dig("arrival", "iataCode")

        # If these key details match, we consider it the same flight
        if offer_origin == origin && offer_destination == destination
          matching_flight = offer
          break
        end
      end

      unless matching_flight
        Rails.logger.error "No matching flight found among search results"
        booking.update(status: "error", notes: "Could not find a matching flight")
        return false
      end

      Rails.logger.info "Found matching flight offer"

      # Step 2: Confirm the price using the pricing endpoint
      pricing_url = "https://test.api.amadeus.com/v1/shopping/flight-offers/pricing"
      pricing_payload = {
        data: {
          type: "flight-offers-pricing",
          flightOffers: [ matching_flight ]
        }
      }

      pricing_response = HTTP.headers(headers).post(pricing_url, json: pricing_payload)

      unless pricing_response.status.success?
        Rails.logger.error "Failed to confirm flight price: #{pricing_response.body}"
        booking.update(status: "error", notes: "Failed to confirm flight price")
        return false
      end

      pricing_data = JSON.parse(pricing_response.body)
      priced_flight_offer = pricing_data.dig("data", "flightOffers", 0)

      # Check if price has changed significantly
      original_price = flight_data["price"].to_f
      current_price = priced_flight_offer.dig("price", "grandTotal").to_f

      # Allow 10% price difference or $10, whichever is greater
      price_tolerance = [ original_price * 0.1, 10.0 ].max

      if (current_price - original_price).abs > price_tolerance
        booking.update(status: "price_changed", notes: "Price changed from #{original_price} to #{current_price}")
        Rails.logger.error "Price changed from #{original_price} to #{current_price}"
        return false
      end

      # Step 3: Create the traveler object and make the booking
      traveler = {
        id: "1",
        dateOfBirth: "1982-01-16",
        name: {
          firstName: booking.first_name,
          lastName: booking.last_name
        },
        contact: {
          emailAddress: booking.email,
          phones: [ {
            deviceType: "MOBILE",
            countryCallingCode: "1",
            number: "5555555555"
          } ]
        }
      }

      booking_url = "https://test.api.amadeus.com/v1/booking/flight-orders"
      booking_payload = {
        data: {
          type: "flight-order",
          flightOffers: [ priced_flight_offer ],
          travelers: [ traveler ]
        }
      }

      Rails.logger.info "Sending booking request with confirmed pricing"
      booking_response = HTTP.headers(headers).post(booking_url, json: booking_payload)

      if booking_response.status.success?
        booking_data = JSON.parse(booking_response.body)
        booking.update(
          status: "confirmed",
          booking_reference: booking_data.dig("data", "id") || booking.booking_reference
        )
        true
      else
        begin
          response_body = JSON.parse(booking_response.body)
          error_code = response_body.dig("errors", 0, "code")
          error_title = response_body.dig("errors", 0, "title")
          error_detail = response_body.dig("errors", 0, "detail")

          Rails.logger.error "Booking API Error: Code=#{error_code}, Title=#{error_title}, Detail=#{error_detail}"

          case error_code
          when 37200 # PRICE DISCREPANCY
            booking.update(status: "price_changed", notes: "Price discrepancy error")
            false
          when 34107 # NOT APPLICABLE FARE
            booking.update(status: "fare_unavailable", notes: "Fare no longer available")
            false
          else
            booking.update(status: "error", notes: "Error: #{error_title}")
            false
          end
        rescue => e
          booking.update(status: "error", notes: "Failed to process API response")
          Rails.logger.error "Error parsing API response: #{e.message}"
          false
        end
      end
    rescue => e
      Rails.logger.error "Exception during flight booking: #{e.message}"
      booking.update(status: "error", notes: "System error: #{e.message}")
      false
    end
  end

  def update_flight_booking(booking)
    # Example PUT request to update booking
    access_token = AmadeusAuthService.new.call

    if access_token && booking.booking_reference.present?
      update_url = "https://test.api.amadeus.com/v1/booking/flight-orders/#{booking.booking_reference}"
      headers = {
        "Authorization" => "Bearer #{access_token}",
        "Content-Type" => "application/json"
      }

      # Example payload for updating passenger details
      traveler = {
        id: "1",
        dateOfBirth: booking.passenger_details&.dig("dateOfBirth") || "1982-01-16",
        name: {
          firstName: booking.first_name,
          lastName: booking.last_name
        },
        contact: {
          emailAddress: booking.email,
          phones: [ {
            deviceType: "MOBILE",
            countryCallingCode: "1",
            number: "5555555555"
          } ]
        }
      }

      payload = {
        data: {
          type: "flight-order",
          id: booking.booking_reference,
          travelers: [ traveler ]
        }
      }

      # Using HTTP gem for PUT request
      response = HTTP.headers(headers).post(update_url, json: payload)

      if response.status.success?
        booking.update(status: "updated")
        true
      else
        Rails.logger.error "Booking Update API Error: #{response.body}"
        false
      end
    else
      Rails.logger.error "Failed to update booking: Missing token or reference"
      false
    end
  end
end
