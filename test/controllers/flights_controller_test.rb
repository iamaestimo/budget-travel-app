require "test_helper"

class FlightsControllerTest < ActionDispatch::IntegrationTest
  test "should get concurrent_search" do
    get flights_concurrent_search_url
    assert_response :success
  end
end
