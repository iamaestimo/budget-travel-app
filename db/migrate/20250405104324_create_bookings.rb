class CreateBookings < ActiveRecord::Migration[8.0]
  def change
    create_table :bookings do |t|
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :email, null: false
      t.integer :flight_id, null: false
      t.string :booking_reference
      t.string :status, default: 'pending'
      t.json :flight_details
      t.json :passenger_details
      t.decimal :amount, precision: 10, scale: 2
      t.string :currency, default: 'USD'

      t.timestamps
    end

    add_index :bookings, :flight_id
    add_index :bookings, :booking_reference, unique: true
  end
end
