Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # Flight routes
  get "advanced_search", to: "home#advanced_search", as: :advanced_search
  post "search_results", to: "home#search_results", as: :search_results

  # Hotel routes
  get "hotel_search", to: "home#hotel_search", as: :hotel_search
  get "hotel_results", to: "home#hotel_results", as: :hotel_results
  get "hotel_details/:hotel_id", to: "home#hotel_details", as: :hotel_details
  get "hotel_offer/:offer_id", to: "home#hotel_details", as: :hotel_offer

  # Home
  root "home#index"
end
