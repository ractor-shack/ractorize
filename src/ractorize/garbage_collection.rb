module Ractorize
  module GarbageCollection
    class << self
      def get_ractor(ractorized_object_id)
        return_port = Ractor::Port.new
        TRACKING_RACTOR << [:get_ractor, ractorized_object_id, return_port].freeze
        ractor = return_port.receive
        return_port.close
        ractor
      end

      def delete_ractor(ractorized_object_id)
        TRACKING_RACTOR << [:delete_ractor, ractorized_object_id].freeze
      end

      def close
        TRACKING_RACTOR << :__close__
      end

      def track_ractorized_object(ractorized_object, ractor)
        puts "track_ractorized_object called for #{ractorized_object.__object_id__} #{ractor}"
        return_port = Ractor::Port.new
        TRACKING_RACTOR << [:track_ractorized_object, ractor, return_port].freeze
        puts "waiting for args_port"
        args_port = return_port.receive
        puts "got args port!"
        args_port.send(ractorized_object, move: true)
        returned_ractorized_object = return_port.receive
        return_port.close
        puts "done track_Ractorized_object #{ractorized_object.__object_id__} #{ractor}"
        returned_ractorized_object
      end

      def track_thunk(thunk, return_value_port)
        return_port = Ractor::Port.new
        TRACKING_RACTOR << [:track_thunk, return_port]

        args_port = return_port.receive
        return_port.close

        args_port.send(thunk, move: true)
        args_port.send(return_value_port)

        args_port.receive
      end

      TRACKING_RACTOR = Ractor.new do
        tracker = RactorizedTracker.new

        loop do
          message = receive

          if Array === message
            puts "got message! #{message.first}"
          else
            puts "got_message #{message}"
          end

          case message
          in :get_ractor, ractorized_object_id, return_port
            return_port << tracker.get_ractor(ractorized_object_id)
            return_port = nil
          in :delete_ractor, ractorized_object_id
            tracker.delete_ractor(ractorized_object_id)
          in :__close__
            tracker = nil
            break
          in :construct_ractorized_object, args, opts, return_port
            return_port.send(
              tracker.construct_ractorized_object(*args, **opts),
              move: true
            )
            args = opts = return_port = nil
          in :construct_thunk, ractorized_object_id, return_value_port, return_port
            return_port.send(
              tracker.construct_thunk(ractorized_object),
              move: true
            )
            return_value_port = return_port = nil
          in :clean_up_after_ractorized_object, ractorized_object_id
            tracker.clean_up_after_ractorized_object(ractorized_object_id)
          in :clean_up_after_thunk, thunk_id
            tracker.clean_up_after_thunk(thunk_id)
          else
            raise "couldn't handle the message #{message}!"
          end
        rescue => e
          puts "wtf got error in tracking ractor loop hmmm #{e}"
          puts e.class
          puts e.message
          puts e.backtrace
          raise
        end
      end

      private_constant :TRACKING_RACTOR
    end
  end
end
