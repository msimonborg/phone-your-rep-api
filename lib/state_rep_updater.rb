# frozen_string_literal: true

# Scrapes data from OpenStates.org and loads into the database
class StateRepUpdater
  attr_reader :state, :open_states_reps

  def self.update!
    metadata = OpenStates.metadata.objects
    metadata.each do |meta|
      state_abbr = meta.abbreviation.upcase
      state      = State.find_by(abbr: state_abbr)
      chambers   = meta.chambers
      state.upper_chamber_title = chambers['upper']['title']
      state.lower_chamber_title = chambers['lower']['title'] if chambers['lower']
      state.save

      open_states_reps = OpenStates.legislators { |r| r.state = state_abbr }.objects
      new(open_states_reps, state_abbr).update!
      OpenStates::Legislator.destroy_all
    end
  end

  def initialize(open_states_reps, state_abbr)
    @state = State.find_by(abbr: state_abbr.upcase)
    @open_states_reps = open_states_reps
  end

  def update!
    open_states_reps.each do |os_rep|
      district = StateDistrict.find_by(state: state, name: os_rep.district, chamber: os_rep.chamber)
      next unless district
      add_or_update_rep(os_rep, district)
    end
  end

  def add_or_update_rep(os_rep, district)
    rep          = StateRep.find_or_initialize_by(official_id: os_rep.leg_id)
    rep.district = district
    rep.state    = state
    update_personal_info(rep, os_rep)
    update_political_info(rep, os_rep)
    rep.add_photo if rep.photo_url != rep.photo
    rep.save

    add_or_update_office_locations(rep, os_rep)
  end

  def update_political_info(rep, os_rep)
    rep.chamber      = os_rep.chamber
    rep.party        = os_rep.party
    rep.contact_form = os_rep.email
    rep.active       = os_rep.active
    rep.photo_url    = os_rep.photo_url
    rep.level        = os_rep.level
    rep.url          = os_rep.url
  end

  def update_personal_info(rep, os_rep)
    rep.official_full = os_rep.full_name
    rep.last          = os_rep.last_name
    rep.first         = os_rep.first_name
    rep.middle        = os_rep.middle_name
    rep.suffix        = os_rep.suffixes
  end

  def add_or_update_office_locations(rep, os_rep)
    os_rep.offices.each do |os_off|
      off = rep.office_locations.find_or_initialize_by(
        office_type: os_off.type, rep: rep
      )
      update_fax_phone_and_address(off, os_off)
      off.save
    end
  end

  def update_fax_phone_and_address(off, os_off)
    off.fax     = !os_off.fax.blank?     ? os_off.fax     : off.fax
    off.phone   = !os_off.phone.blank?   ? os_off.phone   : off.phone
    off.address = !os_off.address.blank? ? os_off.address : off.address
  end
end