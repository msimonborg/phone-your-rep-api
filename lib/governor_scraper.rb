# frozen_string_literal: true

require 'governor_scraper/bio_page'
require 'governor_scraper/panel'

class GovernorScraper
  BASE_URI = 'https://www.nga.org'
  CONN = Faraday.new(url: BASE_URI)

  def self.governors
    @_governors ||= []
  end

  def self.index_page
    @_index_page ||= Nokogiri::HTML(CONN.get('/cms/governors/bios').body)
  end

  def self.panels
    @_panels ||= index_page.css('.panel.panel-default.governors').map do |panel|
      Panel.new(panel)
    end
  end

  def self.scrape
    governors.clear
    panels.each do |panel|
      governor = create(panel)
      puts "Scraped #{governor.official_full} of #{governor.state_name}"
    end
  end

  def self.create(panel)
    new(panel).tap do |g|
      g.build
      g.save
    end
  end

  def self.to_json
    governors.map(&:to_h)
  end

  attr_reader :panel,
              :photo_url,
              :state_name,
              :bio_page,
              :official_full,
              :url,
              :party,
              :office_locations

  def initialize(panel)
    @panel = panel
  end

  def build
    @bio_page      = BioPage.new(panel.bio_page)
    @photo_url     = BASE_URI + panel.image
    @state_name    = panel.state
    @official_full = panel.governor_name
    @url           = bio_page.website
    @party         = bio_page.party

    build_office_locations
  end

  def build_office_locations
    @office_locations = [{
      address: bio_page.address,
      city:    bio_page.city,
      state:   bio_page.state,
      zip:     bio_page.zip,
      phone:   bio_page.phone,
      fax:     bio_page.fax
    },
    {
      address: bio_page.alt_address,
      city:    bio_page.alt_city,
      state:   bio_page.alt_state,
      zip:     bio_page.alt_zip,
      phone:   bio_page.alt_phone,
      fax:     bio_page.alt_fax
     }]
  end

  def save
    self.class.governors << self
    self
  end

  def to_h
    {
      photo_url: photo_url,
      state_name: state_name,
      official_full: official_full,
      url: url,
      party: party,
      office_locations: office_locations
    }
  end

  def inspect
    "#<GovernorScraper panel=#{panel} photo_url=\"#{photo_url}\" "\
      "state_name=\"#{state_name}\" bio_page=#{bio_page} "\
      "official_full=\"#{official_full}\" url=\"#{url}\" "\
      "party=\"#{party}\" office_locations=\"#{office_locations}\">"
  end
end