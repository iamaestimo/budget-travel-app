class Booking < ApplicationRecord
  STATUSES = %w[pending confirmed cancelled price_changed]
end
