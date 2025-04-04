Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # Advanced search (POST request)
  get "advanced_search", to: "home#advanced_search", as: :advanced_search
  post "search_results", to: "home#search_results", as: :search_results

  # Homepage
  root "home#index"
end
