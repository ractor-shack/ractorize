module Ractorize
  module GarbageCollection
    class << self
      def put_ractor(ractorized_object_id, ractor)
        TRACKING_RACTOR << [:put_ractor, ractorized_object_id, ractor].freeze
      end

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

      def create_ractorized_object(object)
        return_port = Ractor::Port.new

        TRACKING_RACTOR.send(
          [:construct_ractorized_object, return_port].freeze
        )

        args_port = return_port.receive

        args_port.send(object, move: true)

        args_port = nil
        ractorized_object = return_port.receive
        return_port.close

        ractorized_object
      end

      def create_ractorized_object_from_class(klass, *args, **opts)
        return_port = Ractor::Port.new

        TRACKING_RACTOR.send(
          [:construct_ractorized_object_from_class, klass, return_port].freeze
        )

        args_port = return_port.receive

        ::Ractorize.send_args(args_port, klass, args, opts)

        args_port = nil
        ractorized_object = return_port.receive
        return_port.close
        ractorized_object
      end

      def create_thunk(ractorized_object_id, return_value_port)
        return_port = Ractor::Port.new

        TRACKING_RACTOR << [
          :construct_thunk,
          ractorized_object_id,
          return_value_port,
          Ractor.current,
          return_port
        ].freeze

        thunk = return_port.receive
        puts "created thunk for ractorized object #{ractorized_object_id}"
        thunk
      end
    end

    TRACKING_RACTOR = Ractor.new do
      tracker = RactorizedTracker.new

      loop do
        message = nil
        message = receive

        message_type = message.is_a?(Array) ? message.first : message
        puts "TRACKING_RACTOR: starting #{message_type} in tracking ractor!"

        case message
        in :put_ractor, ractorized_object_id, ractor
          tracker.put_ractor(ractorized_object_id, ractor)
          ractor = nil
        in :get_ractor, ractorized_object_id, return_port
          return_port << tracker.get_ractor(ractorized_object_id)
          return_port = nil
        in :delete_ractor, ractorized_object_id
          tracker.delete_ractor(ractorized_object_id)
          nil
        in :__close__
          tracker = nil
          break
        in :construct_ractorized_object, return_port
          args_port = Ractor::Port.new
          return_port << args_port

          object = args_port.receive

          args_port.close
          args_port = nil

          return_port.send(
            tracker.construct_ractorized_object(:object, object),
            move: true
          )
          args = object = return_port = nil
        in :construct_ractorized_object_from_class, klass, return_port
          args_port = Ractor::Port.new
          return_port << args_port

          args, opts, block = ::Ractorize.extract_args(args_port)
          args_port.close
          args_port = nil

          return_port.send(
            tracker.construct_ractorized_object(:class, klass, *args, **opts, &block),
            move: true
          )
          args = opts = return_port = block = nil
        in :construct_thunk, ractorized_object_id, return_value_port, created_in_ractor, return_port
          return_port.send(
            tracker.construct_thunk(ractorized_object_id, return_value_port, created_in_ractor),
            move: true
          )
          return_value_port = return_port = created_in_ractor = nil
        in :clean_up_after_ractorized_object, ractorized_object_id
          puts "TRACKING_RACTOR: got cleanup message!!"
          tracker.clean_up_after_ractorized_object(ractorized_object_id)
          nil
        in :clean_up_after_thunk, thunk_id
          tracker.clean_up_after_thunk(thunk_id)
          nil
        in :created_return_port, ractorized_object_id, return_value_port
          tracker.created_return_port(ractorized_object_id, return_value_port)
          return_value_port = nil
        else
          raise "TRACKING_RACTOR: couldn't handle the message #{message}!"
        end

        puts "TRACKING_RACTOR: done with #{message_type} in tracking ractor!"
      rescue => e
        puts "TRACKING_RACTOR: wtf got error in tracking ractor loop hmmm #{e}"
        puts e.class
        puts e.message
        puts e.backtrace
        raise
      end

      puts "TRACKING_RACTOR: hmmmm TRACKING_RACTOR is shutting down..."
    end

    private_constant :TRACKING_RACTOR
  end
end
