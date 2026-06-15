module Ractorize
  module GarbageCollection
    class << self
      def track_ractorized_object(ractorized_object)
        # We have to define the finalizer here, not in the tracker, because it's not frozen yet
        ObjectSpace.define_finalizer(ractorized_object, &finalize_proc)
        Object.instance_method(:freeze).bind_call(ractorized_object)

        puts "tracking ro #{ractorized_object.__object_id__}"

        TRACKING_RACTOR << [:track_ractorized_object, ractorized_object].freeze
      end

      def cleanup_after_ractorized_object(ractorized_object_id)
        TRACKING_RACTOR << [:cleanup_after_ractorized_object, ractorized_object_id].freeze
      rescue Ractor::ClosedError
        # do nothing
      end

      private

      def finalize_proc
        proc do |ractorized_object_id|
          puts "cleaning up after ractorized object #{ractorized_object_id}!"
          ::Ractorize::GarbageCollection.cleanup_after_ractorized_object(ractorized_object_id)
        end
      end
    end

    TRACKING_RACTOR = Ractor.new do
      tracker = Tracker.new

      loop do
        case receive
        in :track_ractorized_object, ractorized_object
          tracker.track_ractorized_object(ractorized_object)
          ractorized_object = nil
        in :cleanup_after_ractorized_object, ractorized_object_id
          tracker.cleanup_after_ractorized_object(ractorized_object_id)
        end
      end
    end

    private_constant :TRACKING_RACTOR
  end
end
