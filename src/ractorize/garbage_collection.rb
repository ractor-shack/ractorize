module Ractorize
  module GarbageCollection
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
        # We have to define the finalizer here, not in the tracker, because it's not shareable
        ObjectSpace.define_finalizer(thunk, &finalize_thunk_proc)

        begin
          TRACKING_RACTOR << [:track_thunk, thunk.__object_id__, thunk.__thunk_ractor__].freeze
        rescue TrackingRactor::ClosedError
          # do nothing
        end
      end

      def thunk_cloned(old_thunk, new_thunk)
        ractor = old_thunk.__thunk_ractor__

        # We have to define the finalizer here, not in the tracker, because it's not shareable
        # ObjectSpace.define_finalizer(new_thunk, &finalize_thunk_proc)

        begin
          TRACKING_RACTOR << [
            :thunk_cloned,
            old_thunk.__object_id__,
            new_thunk.__object_id__,
            ractor
          ].freeze
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
  end
end
