# frozen_string_literal: true

module Geographic
  extend ActiveSupport::Concern

  FACTORY = RGeo::Geographic.simple_mercator_factory
  EWKB = RGeo::WKRep::WKBGenerator.new(
    type_format:    :ewkb,
    emit_ewkb_srid: true,
    hex_format:     true
  )

  class_methods do
    def containing_latlon(lat, lon)
      point = FACTORY.point(lon, lat)
      containing_point(point)
    end

    def containing_point(point)
      ewkb = EWKB.generate(point.projection)
      where('ST_Intersects(geom, ST_GeomFromEWKB(E?))', "\\\\x#{ewkb}")
    end
  end
end
