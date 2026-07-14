require_relative "../base_ractor"
require_relative "tracker"

module Ractorize
  module GarbageCollection
    class TrackingRactor < BaseRactor
      class << self
        def new
          super(name: "GarbageCollection::TrackingRactor") do
            tracker = Tracker.new

            loop do
              tracker.send(*receive)
            rescue TrackingRactor::ClosedError
              # do nothing
            end
          end
        end
      end
    end

    TRACKING_RACTOR = TrackingRactor.new
    private_constant :TRACKING_RACTOR
  end
end
