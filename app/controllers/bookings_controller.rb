class BookingsController < ApplicationController
  before_action :set_booking, only: [ :show, :edit, :update ]

  def new
    @booking = Booking.new
    @flight_id = params[:flight_id]

    # Get original flight details from the search
    @original_flight_details = JSON.parse(params[:flight_details]) if params[:flight_details].present?

    # Get current pricing from Amadeus
    access_token = AmadeusAuthService.new.call
    if access_token
      current_price_data = get_current_flight_price(@flight_id, access_token, full_details: true)

      if current_price_data
        @current_price = current_price_data[:price]
        @price_changed = @original_flight_details && @current_price != @original_flight_details["price"].to_f

        # Update flight details with current price
        if @original_flight_details
          @flight_details = @original_flight_details.dup
          @flight_details["price"] = @current_price.to_s
          @flight_details["original_price"] = @original_flight_details["price"]
        end
      else
        @error = "Unable to retrieve current pricing for this flight."
      end
    else
      @error = "Unable to connect to flight service."
    end
  end

  def create
    @booking = Booking.new(booking_params)

    # Generate a random booking reference
    @booking.booking_reference = generate_booking_reference

    # Store flight details
    @booking.flight_details = JSON.parse(params[:flight_details]) if params[:flight_details].present?

    if @booking.save
      # Make a POST request to Amadeus Flight Create Orders API (demonstrative)
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
      @flight_id = params[:booking][:flight_id]
      @flight_details = JSON.parse(params[:flight_details]) if params[:flight_details].present?
      render :new, status: :unprocessable_entity
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

  def get_current_flight_price(flight_id, access_token, full_details: false)
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

    if full_details
      {
        price: flight_data.dig("price", "total").to_f,
        currency: flight_data.dig("price", "currency"),
        flight_data: flight_data  # Return the full flight data for use in booking
      }
    else
      flight_data.dig("price", "total").to_f
    end
  end

  def create_flight_booking(booking)
    access_token = AmadeusAuthService.new.call
    return false unless access_token

    flight_data = booking.flight_details

    # If we're using the previously verified current price,
    # we don't need to check for price discrepancy

    booking_url = "https://test.api.amadeus.com/v1/booking/flight-orders"
    headers = {
      "Authorization" => "Bearer #{access_token}",
      "Content-Type" => "application/json"
    }

    payload = {
      data: {
        type: "flight-order",
        flightOffers: [ {
          type: "flight-offer",
          id: flight_data["id"],
          source: "GDS",
          instantTicketingRequired: false,
          nonHomogeneous: false,
          oneWay: true,
          validatingAirlineCodes: [ flight_data["airline"] ],
          itineraries: [ {
            segments: flight_data["segments"].map.with_index(1) do |segment, index|
              {
                id: index.to_s,
                departure: {
                  iataCode: segment["departure_airport"],
                  terminal: segment["departure_terminal"],
                  at: segment["departure_time"]
                },
                arrival: {
                  iataCode: segment["arrival_airport"],
                  terminal: segment["arrival_terminal"],
                  at: segment["arrival_time"]
                },
                carrierCode: segment["carrier"],
                number: segment["flight_number"],
                aircraft: {
                  code: segment["aircraft"]
                },
                duration: segment["duration"]
              }
            end
          } ],
          price: {
            currency: flight_data["currency"],
            total: flight_data["price"],
            baseAmount: flight_data["price"]
          },
          travelerPricings: [ {
            travelerId: "1",
            fareOption: "STANDARD",
            travelerType: "ADULT",
            price: {
              currency: flight_data["currency"],
              total: flight_data["price"],
              base: flight_data["price"]
            },
            fareDetailsBySegment: flight_data["segments"].map.with_index(1) do |segment, index|
              {
                segmentId: index.to_s,
                cabin: flight_data["cabin_class"],
                fareBasis: "Y",
                class: "Y"
              }
            end
          } ]
        } ],
        travelers: [ {
          id: "1",
          dateOfBirth: "1982-01-16",
          name: {
            firstName: booking.first_name,
            lastName: booking.last_name
          },
          contact: {
            emailAddress: booking.email
          }
        } ]
      }
    }

    response = HTTP.headers(headers).post(booking_url, json: payload)

    if response.status.success?
      booking_data = JSON.parse(response.body)
      booking.update(
        status: "confirmed",
        booking_reference: booking_data.dig("data", "id") || booking.booking_reference
      )
      true
    else
      Rails.logger.error "Booking API Error: #{response.body}"
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
      payload = {
        data: {
          type: "flight-order",
          id: booking.booking_reference,
          travelers: [
            {
              id: "1",
              dateOfBirth: booking.passenger_details&.dig("dateOfBirth") || "1982-01-16",
              name: {
                firstName: booking.first_name,
                lastName: booking.last_name
              },
              contact: {
                emailAddress: booking.email
              }
            }
          ]
        }
      }

      # Using HTTP gem for PUT request
      response = HTTP.headers(headers).put(update_url, json: payload)

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
