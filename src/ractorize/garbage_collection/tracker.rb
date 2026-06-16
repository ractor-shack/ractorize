module Ractorize
  module GarbageCollection
    class Tracker
      attr_accessor :ractorized_object_id_to_ractor

      def initialize
        self.ractorized_object_id_to_ractor = ObjectSpace::WeakMap.new
      end

      def track_ractorized_object(ractorized_object)
        ractorized_object_id_to_ractor[ractorized_object.__object_id__] = ractorized_object.__ractor__
      end

      def cleanup_after_ractorized_object(ractorized_object_id)
        ractor = ractorized_object_id_to_ractor.delete(ractorized_object_id)
        ractor&.<<(:__close__)
      end
    end
  end
end
