Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # flights
  get "advanced_search", to: "home#advanced_search", as: :advanced_search
  post "search_results", to: "home#search_results", as: :search_results

  # bookings
  resources :bookings, only: [ :new, :create, :show, :edit, :update ]

  # home
  root "home#index"
end
