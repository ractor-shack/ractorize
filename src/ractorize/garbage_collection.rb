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
        TRACKING_RACTOR << [:track_ractorized_object, ractorized_object, ractor].freeze
      end

      def track_thunk(thunk, return_value_port)
        return_port = Ractor::Port.new
        RACTOR_TRACKER << [:track_thunk, return_port]

        args_port = return_port.receive
        return_port.close

        args_port.send(thunk, move: true)
        args_port.send(return_value_port)

        args_port.receive
      end

      TRACKING_RACTOR = Ractor.new do
        ractorized_object_id_to_ractor = {}
        ractorized_object_id_to_return_ports = {}
        thunk_id_to_ractorized_object_id = {}

        loop do
          case receive
          in :get_ractor, ractorized_object_id, return_port
            return_port << ractorized_object_id_to_ractor[ractorized_object_id]
            return_port = nil
          in :delete_ractor, ractorized_object_id
            ractorized_object_id_to_ractor.delete(ractorized_object_id)
          in :__close__
            break
          in :track_ractorized_object, ractorized_object, ractor
            ractorized_object_id_to_ractor[ractorized_object.__object_id__] = ractor
            setup_ractorized_object_finalizer(ractorized_object)
            ractorized_object = ractor = nil
          in :track_thunk, return_port
            args_port = Ractor::Port.new

            return_port << args_port

            thunk = args_port.receive
            return_value_port = args_port.receive

            ractorized_object_id = thunk.__ractorized_object_id__
            thunk_id = thunk.__object_id__

            return_ports = ractorized_object_id_to_return_ports[ractorized_object_id] ||= ObjectSpace::WeakMap.new
            return_ports[thunk_id] = return_value_port

            thunk_id_to_ractorized_object_id[thunk_id] = ractorized_object_id

            setup_thunk_finalizer(thunk)

            args_port.send(thunk, move: true)

            args_port = thunk = return_port = return_ports = return_value_port = nil
          in :clean_up_after_ractorized_object, ractorized_object_id
            ractor = ractorized_object_id_to_ractor.delete(ractorized_object_id)

            if ractor
              thunk_id_to_port = ractorized_object_id_to_return_ports.delete(ractorized_object_id)

              ports = thunk_id_to_port.values

              ractor << if ports&.any?
                          [:__abandon_ports_and_close__, [ports].freeze].freeze
                        else
                          :__close__
                        end rescue Ractor::ClosedError

              thunk_id_to_port.each_key do |thunk_id|
                thunk_id_to_ractorized_object_id.delete(thunk_id)
              end

              ports = thunk_id_to_port = ractor = nil
            end
          in :clean_up_after_thunk, thunk_id
            ractorized_object_id = thunk_id_to_ractorized_object_id.delete(thunk_id)
            ractor = ractorized_object_id_to_ractor[ractorized_object_id]
            port = ractorized_object_id_to_return_ports[ractorized_object_id]&.delete(thunk_id)

            if ractor
              if port
                ractor << [:__close_port__, port].freeze rescue Ractor::ClosedError
                port = nil
              end

              ractor = nil
            end
          end
        end
      end

      private_constant :TRACKING_RACTOR

      private

      def ractorized_object_finalize_proc
        proc do |ractorized_object_id|
          puts "finalizer called for #{ractorized_object_id}!!!"
          TRACKING_RACTOR << [:clean_up_after_ractorized_object, ractorized_object_id].freeze rescue Ractor::ClosedError
        end
      end

      def setup_ractorized_object_finalizer(proxy_object)
        ObjectSpace.define_finalizer(proxy_object, &finalize_proc)
      end

      def thunk_finalize_proc
        proc do |thunk_id|
          puts "thunk finalizer called for #{thunk_id}!!!"
          TRACKING_RACTOR << [:clean_up_after_thunk, thunk_id].freeze rescue Ractor::ClosedError
        end
      end

      def setup_thunk_finalizer(thunk)
        ObjectSpace.define_finalizer(thunk, &finalize_proc)
      end
    end
  end
end
