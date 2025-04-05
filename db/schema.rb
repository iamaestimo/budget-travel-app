# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_04_05_104324) do
  create_table "bookings", force: :cascade do |t|
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.string "email", null: false
    t.integer "flight_id", null: false
    t.string "booking_reference"
    t.string "status", default: "pending"
    t.json "flight_details"
    t.json "passenger_details"
    t.decimal "amount", precision: 10, scale: 2
    t.string "currency", default: "USD"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_reference"], name: "index_bookings_on_booking_reference", unique: true
    t.index ["flight_id"], name: "index_bookings_on_flight_id"
  end
end
