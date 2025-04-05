class FlightsController < ApplicationController
  def concurrent_search
    if request.post?
      origins = params[:origins].reject(&:blank?)
      destinations = params[:destinations].reject(&:blank?)
      dates = params[:dates].reject(&:blank?)

      Async do
        access_token = AmadeusAuthService.new.call
        @results = search_concurrent_flights(origins, destinations, dates, access_token)
        render turbo_stream: turbo_stream.update("results",
          partial: "comparison_results",
          locals: { results: @results })
      end
    end
  end

  private

  def search_concurrent_flights(origins, destinations, dates, access_token)
    internet = Async::HTTP::Internet.new
    headers = [
      [ "authorization", "Bearer #{access_token}" ],
      [ "accept", "application/json" ]
    ]

    tasks = origins.each_with_index.map do |origin, i|
      destination = destinations[i]
      date = dates[i]

      Async do
        url = "https://test.api.amadeus.com/v2/shopping/flight-offers?" +
              "originLocationCode=#{origin}&" +
              "destinationLocationCode=#{destination}&" +
              "departureDate=#{date}&" +
              "adults=1"

        begin
          response = internet.get(url, headers)
          if response.status == 200
            data = JSON.parse(response.read)
            flights = data.dig("data", 0)
            { origin: origin, destination: destination, flights: flights }
          end
        rescue => e
          Rails.logger.error "Flight search failed for #{origin}-#{destination}: #{e.message}"
          nil
        end
      end
    end

    tasks.map(&:wait).compact
  ensure
    internet.close if defined?(internet)
  end
end
