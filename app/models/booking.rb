class Booking < ApplicationRecord
  STATUSES = %w[pending confirmed cancelled price_changed fare_unavailable updated error]

  validates :first_name, :last_name, :email, :flight_id, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :status, inclusion: { in: STATUSES }

  # Default status to pending if not specified
  after_initialize :set_default_status, if: :new_record?

  private

  def set_default_status
    self.status ||= "pending"
  end
end
