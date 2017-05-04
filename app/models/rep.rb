# frozen_string_literal: true

class Rep < ApplicationRecord
  belongs_to :district
  belongs_to :state
  has_one    :avatar, dependent: :destroy
  has_many   :office_locations,
             dependent: :destroy,
             foreign_key: :bioguide_id,
             primary_key: :bioguide_id
  has_many   :active_office_locations,
             -> { where(active: true) },
             class_name: 'OfficeLocation',
             foreign_key: :bioguide_id,
             primary_key: :bioguide_id

  scope :by_location, lambda { |state:, district:|
    where(district: district).or(Rep.where(state: state, district: nil)).active.distinct
  }

  scope :active, lambda {
    where(active: true).includes(:district, :state, :active_office_locations)
  }

  scope :republican, -> { where party: 'Republican' }

  scope :democrat, -> { where party: 'Democrat' }

  scope :independent, -> { where party: 'Independent' }

  serialize :committees, Array

  is_impressionable

  # Instance attribute that holds offices sorted by location after calling the :sort_offices method.
  attr_accessor :sorted_offices

  # Sort the offices by proximity to the request coordinates,
  # making sure to not miss offices that aren't geocoded.
  def sort_offices(coordinates)
    closest_offices       = active_office_locations.near(coordinates, 4000)
    closest_offices      += active_office_locations
    self.sorted_offices   = closest_offices.uniq || []
    return [] if sorted_offices.blank?
    sorted_offices.each { |office| office.calculate_distance(coordinates) }
  end

  # Protect against nil type errors.
  def district_code
    district.try(:code)
  end

  # Return office_locations even if they were never sorted.
  def sorted_offices_array
    sorted_offices || active_office_locations.order(:office_id)
  end

  def add_photo
    fetch_avatar_data
    update photo: avatar.data ? photo_slug : nil
  end

  def photo_slug
    "https://phoneyourrep.github.io/images/congress/450x550/#{bioguide_id}.jpg"
  end

  def fetch_avatar_data
    ava = avatar || build_avatar
    ava.fetch_data photo_slug
  end
end
