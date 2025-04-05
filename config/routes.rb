Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # flights
  get "advanced_search", to: "home#advanced_search", as: :advanced_search
  post "search_results", to: "home#search_results", as: :search_results
  match "flights/concurrent_search", to: "flights#concurrent_search",
        via: [ :get, :post ], as: :concurrent_search_flights

  # bookings
  resources :bookings, only: [ :new, :create, :show, :edit, :update ]

  # home
  root "home#index"
end
