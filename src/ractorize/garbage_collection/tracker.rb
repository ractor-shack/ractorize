module Ractorize
  module GarbageCollection
    class Tracker
      attr_accessor :ractorized_object_id_to_ractor,
                    :thunk_id_to_ractor,
                    :ractor_to_thunk_ids

      def initialize
        self.ractorized_object_id_to_ractor = ObjectSpace::WeakMap.new
        self.thunk_id_to_ractor = ObjectSpace::WeakMap.new
        self.ractor_to_thunk_ids = ObjectSpace::WeakKeyMap.new
      end

      def track_ractorized_object(ractorized_object)
        ractorized_object_id_to_ractor[ractorized_object.__object_id__] = ractorized_object.__ractor__
      end

      def cleanup_after_ractorized_object(ractorized_object_id)
        ractor = ractorized_object_id_to_ractor.delete(ractorized_object_id)
        ractor&.<<(:__close__)
      rescue Ractor::ClosedError
        # do nothing
      end

      def track_thunk(thunk_id, ractor)
        thunk_id_to_ractor[thunk_id] = ractor
      end

      def thunk_cloned(old_thunk_id, new_thunk_id, thunk_ractor)
        thunk_ids = ractor_to_thunk_ids[thunk_ractor]

        if thunk_ids
          thunk_ids << new_thunk_id
        else
          ractor_to_thunk_ids[thunk_ractor] = [old_thunk_id, new_thunk_id]
        end

        thunk_id_to_ractor[new_thunk_id] = thunk_ractor
      end

      def cleanup_after_thunk(thunk_id)
        ractor = thunk_id_to_ractor.delete(thunk_id)

        unless ractor
          thunk_id_to_ractor.to_h.inspect
        end

        return unless ractor

        thunk_ids = ractor_to_thunk_ids[ractor]

        if thunk_ids
          thunk_ids.delete(thunk_id)

          return unless thunk_ids.empty?
        end

        ractor << :__close__
      rescue Ractor::ClosedError
        # do nothing
      end
    end
  end
end
