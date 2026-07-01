module Ractorize
  module GarbageCollection
    class Tracker
      attr_accessor :ractorized_object_id_to_ractor,
                    :thunk_id_to_ractor,
                    :ractor_to_thunk_ids

      def initialize
        puts "initializing tracker!"
        self.ractorized_object_id_to_ractor = ObjectSpace::WeakMap.new
        self.thunk_id_to_ractor = ObjectSpace::WeakMap.new
        self.ractor_to_thunk_ids = ObjectSpace::WeakKeyMap.new
      end

      def track_ractorized_object(ractorized_object)
        ractorized_object_id_to_ractor[ractorized_object.__object_id__] = ractorized_object.__ractor__
      end

      def cleanup_after_ractorized_object(ractorized_object_id)
        puts "cleaning up after ractorized object!! hmmmmm"
        ractor = ractorized_object_id_to_ractor.delete(ractorized_object_id)
        ractor&.<<(:__close__)
      rescue Ractor::ClosedError
        # do nothing
      end

      def track_thunk(thunk_id, ractor)
        puts "tracking thunk #{thunk_id} to #{ractor}"
        thunk_id_to_ractor[thunk_id] = ractor
      end

      def thunk_cloned(old_thunk_id, new_thunk_id, thunk_ractor)
        thunk_ids = ractor_to_thunk_ids[thunk_ractor]

        if thunk_ids
          puts "appending!!"
          thunk_ids << new_thunk_id
        else
          puts "starting with a pair"
          ractor_to_thunk_ids[thunk_ractor] = [old_thunk_id, new_thunk_id]
        end

        thunk_id_to_ractor[new_thunk_id] = thunk_ractor

        puts "done cloning:"

        # pp thunk_id_to_ractor.to_h
        # pp ractor_to_thunk_ids.to_h
        #
        puts ::Object.instance_method(:class).bind_call(thunk_ractor)
      end

      def cleanup_after_thunk(thunk_id)
        puts "cleaning up after #{thunk_id}"
        ractor = thunk_id_to_ractor.delete(thunk_id)

        unless ractor
          puts "wtf no ractors???"
          thunk_id_to_ractor.to_h.inspect
        end

        return unless ractor

        thunk_ids = ractor_to_thunk_ids[ractor]

        if thunk_ids.nil?
          puts "wtf no thunk ids???"
          # pp ractor_to_thunk_ids.keys.map(&:inspect)
        else
          puts "thunk_ids are #{thunk_ids.inspect}"
        end

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
