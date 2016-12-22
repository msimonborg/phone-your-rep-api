class Rep < ApplicationRecord
  belongs_to :district
  belongs_to :state
  has_many   :office_locations, dependent: :destroy
  serialize  :committees, Array
  serialize  :email, Array

  ##
  # Map the phone number of every office location into one Array.
  def phone
    self.office_locations.map { |loc| loc.phone }
  end

  ##
  # Find the reps in the db associated to that address and assemble into JSON blob
  def self.get_em(address)
    @address = address
    self.get_coordinates
    self.get_state
    self.get_district
    self.get_raw_state_and_district_reps
    self.cook_the_reps
  end

  ##
  # Geocode address into [lat, lon] coordinates.
  def self.get_coordinates
    @coordinates = Geocoder.coordinates(@address)
  end

  ##
  # Parse out the two letter state abbreviation from address and find the State by that attribute.
  def self.get_state
    state_abbr = @address.split.grep(/[A-Z]{2}/)
    @state = State.where(abbr: state_abbr).first
  end

  ##
  # Query all of the districts within that state by :state_code foreign key.
  # Collect the lat and lon from the coordinates and create a new RGeo Point object.
  # Select the district from the collection of state districts that contains the point.
  def self.get_district
    districts = @state.districts
    lat = @coordinates.first
    lon = @coordinates.last
    point = RGeo::Cartesian.factory.point(lon, lat)
    @district = districts.select { |district| point.within?(district.geom) }
  end

  ##
  # Query for Reps that belong to either the state or the district.
  # Add the reps to a @raw_reps array.
  def self.get_raw_state_and_district_reps
    @raw_reps = []
    @raw_reps += Rep.where(state: @state, district: @district).map { |rep| rep }
    @raw_reps += Rep.where(state: @state, district: nil).map { |rep| rep }
    @raw_reps = @raw_reps.uniq
  end

  ##
  # Instantiate a new Delegation. Iterate over @raw_reps and assemble their attributes into a new
  # Representative. Structure the Representative to be used as a JSON blob.
  def self.cook_the_reps
    @cooked_reps = GetYourRep::Delegation.new
    @raw_reps.each do |rep|
      self.sort_offices(rep)
      @cooked_reps << GetYourRep::Representative[
        :name,             rep.name,
        :state,            rep.state.abbr,
        :district,         (rep.district.code if rep.district),
        :office,           rep.office,
        :party,            self.party(rep.party),
        :phone,            self.phones(rep),
        :office_locations, self.offices(rep),
        :email,            rep.email,
        :url,              rep.url,
        :photo,            rep.photo,
        :twitter,          rep.twitter,
        :facebook,         rep.facebook,
        :youtube,          rep.youtube,
        :googleplus,       rep.googleplus
      ]
    end
    @cooked_reps
  end

  ##
  # Sort the offices by proximity to the request coordinates
  def self.sort_offices(rep)
    @sorted_offices = rep.office_locations.near(@coordinates, 4000)
  end

  ##
  # Map the phones in order of the sorted offices
  def self.phones(rep)
    @sorted_offices.map { |office| office.phone } - [nil]
  end

  ##
  # Parse the rep's office locations into hashes and map them in the sorted order.
  def self.offices(rep)
    @sorted_offices.map do |office|
      {
        type:   office.office_type,
        line_1: office.line1,
        line_2: office.line2,
        line_3: office.line3,
        line_4: office.line4,
        line_5: office.line5
      }
    end
  end

  ######
  # The methods below are used to pull in rep data from the Google and Open States APIs and
  # update the database

  def self.get_top_reps(address)
    @new_reps = []
    @address = address
    self.get_state
    @reps = GetYourRep::Google.top_level_reps(address)
    @db_reps = self.where(last_name: @reps.last_names, first_name: @reps.first_names)
    self.update_rep_info_to_db
    @new_reps.each { |new_rep| new_rep.save } unless @new_reps.blank?
    @reps
  end

  def self.get_state_reps(address)
    GetYourRep::OpenStates.now(address)
  end

  def self.update_rep_info_to_db
    @reps.each do |rep|
      @db_rep = @db_reps.select { |db_rep| db_rep.last_name == rep.last_name }.first
      if @db_rep.blank?
        self.add_rep_to_db(rep)
      else
        self.update(rep)
      end
    end
  end

  def self.add_rep_to_db(rep)
    self.parse_new_rep_district(rep)

    new_rep  = Rep.new
    new_rep.state      = @state
    new_rep.district   = District.where(code: @rep_district, state_code: @state.state_code).first
    new_rep.office     = rep.office
    new_rep.name       = rep.name
    new_rep.last_name  = rep.last_name
    new_rep.first_name = rep.first_name
    new_rep.party      = rep.party
    new_rep.email      = rep.email
    new_rep.url        = rep.url
    new_rep.twitter    = rep.twitter
    new_rep.facebook   = rep.facebook
    new_rep.youtube    = rep.youtube
    new_rep.googleplus = rep.googleplus
    new_rep.photo      = rep.photo
    new_rep.committees = rep.committees

    self.build_district_office(new_rep, rep)
    self.build_capitol_office(new_rep, rep)
    @new_reps << new_rep
  end

  def self.build_district_office(new_rep, rep)
    unless rep.district_office.blank?
      d_o             = new_rep.office_locations.build
      d_o.office_type = 'district'
      d_o.line1       = rep.district_office[:line_1]
      d_o.line2       = rep.district_office[:line_2]
      d_o.line3       = rep.district_office[:line_3]
      d_o.phone       = rep.phone.first
    end
  end

  def self.build_capitol_office(new_rep, rep)
    unless rep.capitol_office.blank?
      c_o             = new_rep.office_locations.build
      c_o.office_type = 'capitol'
      c_o.line1       = rep.capitol_office[:line_1]
      c_o.line2       = rep.capitol_office[:line_2]
      c_o.line3       = rep.capitol_office[:line_3]
      c_o.phone       = rep.phone.last
    end
  end

  def self.parse_new_rep_district(rep)

    if rep.office.downcase.match(/(united states house)/)
      office_suffix = rep.office.split(' ').last
      @rep_district = office_suffix.split('-').last

    elsif rep.office.downcase.match(/(united states senate)|(governor)/)
      @rep_district = nil

    elsif rep.office.downcase.match(/upper|lower|chamber/)
      office_array  = rep.office.split(' ')
      @rep_district = office_array.last

    end
  end

  def self.update(rep)
    @update_params = {}
    @update_params[:state]  = @state     if @db_rep.state.nil?
    @update_params[:office] = rep.office if @db_rep.office != rep.office
    @update_params[:party]  = rep.party  if @db_rep.party  != rep.party
    self.update_email(rep)
    self.update_social_handles(rep)
    self.update_or_create_capitol_address(rep)
    self.update_committees(rep)
    @db_rep.update(@update_params) unless @update_params.blank?
  end

  def self.update_email(rep)
    unless (rep.email - @db_rep.email).empty?
      @update_params[:email] = (@db_rep.email += rep.email)
    end
  end

  def self.update_social_handles(rep)
    @update_params[:twitter]    = rep.twitter    if @db_rep.twitter    != rep.twitter
    @update_params[:facebook]   = rep.facebook   if @db_rep.facebook   != rep.facebook
    @update_params[:youtube]    = rep.youtube    if @db_rep.youtube    != rep.youtube
    @update_params[:googleplus] = rep.googleplus if @db_rep.googleplus != rep.googleplus
  end

  def self.update_or_create_capitol_address(rep)
    return unless rep.capitol_office
    self.gather_office_locations
    if @capitol_office.nil?
      self.create_capitol_address(rep)
    else
      self.update_capitol_address(rep)
    end
  end

  def self.create_capitol_address(rep)
    @db_rep.office_locations.build(
      office_type: rep.capitol_office[:type],
      line1:       rep.capitol_office[:line_1],
      line2:       rep.capitol_office[:line_2],
      line3:       rep.capitol_office[:line_3],
      line4:       rep.capitol_office[:line_4],
      line5:       rep.capitol_office[:line_5],
    )
  end

  def self.update_capitol_address(rep)
    @cap_office_update_params = {}

    if @capitol_office.line1 != rep.capitol_office[:line_1]
      @cap_office_update_params[:line1] = rep.capitol_office[:line_1]
    end

    if @capitol_office.line2 != rep.capitol_office[:line_2]
      @cap_office_update_params[:line2] = rep.capitol_office[:line_2]
    end

    if @capitol_office.line3 != rep.capitol_office[:line_3]
      @cap_office_update_params[:line3] = rep.capitol_office[:line_3]
    end

    @capitol_office.update(@cap_office_update_params) unless @cap_office_update_params.blank?
  end

  def self.gather_office_locations
    @db_rep_offices = @db_rep.office_locations
    @capitol_office = @db_rep_offices.map { |office| office if office.office_type == 'capitol' }[0]
  end

  def self.update_committees(rep)
    unless rep.committees.nil? || (rep.committees - @db_rep.committees).empty?
      @update_params[:committees] = (@db_rep.committees += rep.committees)
    end
  end

  def self.random_rep
    random_rep = Rep.order("RANDOM()").limit(1).first
    return Hash[:error, 'Something went wrong, try again.'].to_a if random_rep.nil?
    offices = random_rep.office_locations.map do |office|
      {
        type:   office.office_type,
        line_1: office.line1,
        line_2: office.line2,
        line_3: office.line3
      }
    end
    GetYourRep::Representative[
      :name,             random_rep.name,
      :office,           random_rep.office,
      :party,            party(random_rep.party),
      :phone,            random_rep.phone,
      :office_locations, offices,
      :email,            random_rep.email,
      :url,              random_rep.url,
      :photo,            random_rep.photo,
      :twitter,          random_rep.twitter,
      :facebook,         random_rep.facebook,
      :youtube,          random_rep.youtube,
      :googleplus,       random_rep.googleplus
    ].to_del
  end

  def self.party(value)
    case value
    when 'D'
      'Democratic'
    when 'R'
      'Republican'
    when 'I'
      'Independent'
    else
      value
    end
  end

  def self.update_rep_info_from_db
    @reps.each do |rep|
      @db_rep = @db_reps.select { |db_rep| db_rep.last_name == rep.last_name }.first

      if @db_rep.blank?
        add_rep_to_db(rep)
      else

        @db_rep_offices = @db_rep.office_locations
        district_offices = @db_rep_offices.map { |office| office if office.office_type == 'district'}
        district_offices -= [nil]

        rep.phone = (rep.phone + @db_rep.phone).uniq - [nil]
        (rep.email += (@db_rep.email).flatten).uniq

        if rep.district_office.empty? && district_offices
          district_offices.each do |district_office|
            rep.office_locations.unshift Hash[
              :type,   district_office.office_type,
              :line_1, district_office.line1,
              :line_2, district_office.line2,
              :line_3, district_office.line3,
              :line_4, district_office.line4,
              :line_5, district_office.line5
            ]
          end
        end

      update_rep_info_to_db(rep)
      end
    end
  end
end
