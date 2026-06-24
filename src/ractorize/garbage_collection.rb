module Ractorize
  module GarbageCollection
    class TrackingRactor < BaseRactor; end

    class << self
      def track_ractorized_object(ractorized_object)
        # We have to define the finalizer here, not in the tracker, because it's not frozen yet
        ObjectSpace.define_finalizer(ractorized_object, &finalize_proc)
        Object.instance_method(:freeze).bind_call(ractorized_object)

        begin
          TRACKING_RACTOR << [:track_ractorized_object, ractorized_object].freeze
        rescue TrackingRactor::ClosedError
          # do nothing
        end
      end

      def track_thunk(thunk)
        # We have to define the finalizer here, not in the tracker, because it's not frozen yet
        ObjectSpace.define_finalizer(thunk, &finalize_thunk_proc)

        begin
          TRACKING_RACTOR << [:track_thunk, thunk.__object_id__, thunk.__thunk_ractor__].freeze
        rescue TrackingRactor::ClosedError
          # do nothing
        end
      end

      def cleanup_after_ractorized_object(ractorized_object_id)
        TRACKING_RACTOR << [:cleanup_after_ractorized_object, ractorized_object_id].freeze
      rescue Ractor::ClosedError
        # do nothing
      end

      def cleanup_after_thunk(thunk_id)
        TRACKING_RACTOR << [:cleanup_after_thunk, thunk_id].freeze
      rescue Ractor::ClosedError
        # do nothing
      end

      private

      def finalize_proc
        proc do |ractorized_object_id|
          ::Ractorize::GarbageCollection.cleanup_after_ractorized_object(ractorized_object_id)
        end
      end

      def finalize_thunk_proc
        proc do |thunk_id|
          ::Ractorize::GarbageCollection.cleanup_after_thunk(thunk_id)
        end
      end
    end

    TRACKING_RACTOR = TrackingRactor.new do
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
        in :cleanup_after_thunk, thunk_id
          tracker.cleanup_after_thunk(thunk_id)
        end
      rescue TrackingRactor::ClosedError
        # do nothing
      end
    end

    private_constant :TRACKING_RACTOR
  end
end
