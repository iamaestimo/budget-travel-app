class AddColumnNotesToBooking < ActiveRecord::Migration[8.0]
  def change
    add_column :bookings, :notes, :string
  end
end
