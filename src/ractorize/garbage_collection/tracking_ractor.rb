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
              # SimpleCov branch coverage doesn't like that we aren't testing not matching anything
              # but this does result in an error unlike case/when so no point in checking that.
              # :nocov:
              case receive
                # :nocov:
              in :track_ractorized_object, ractorized_object
                tracker.track_ractorized_object(ractorized_object)
              in :cleanup_after_ractorized_object, ractorized_object_id
                tracker.cleanup_after_ractorized_object(ractorized_object_id)
              in :track_thunk, thunk_id, thunk_ractor
                tracker.track_thunk(thunk_id, thunk_ractor)
              in :thunk_cloned, old_thunk_id, new_thunk_id, thunk_ractor
                tracker.thunk_cloned(old_thunk_id, new_thunk_id, thunk_ractor)
              in :cleanup_after_thunk, thunk_id
                tracker.cleanup_after_thunk(thunk_id)
              end
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
