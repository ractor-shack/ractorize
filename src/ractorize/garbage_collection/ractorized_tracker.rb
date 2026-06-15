module Ractorize
  module GarbageCollection
    class RactorizedTracker
      attr_accessor :ractorized_object_id_to_ractor,
                    :ractorized_object_id_to_return_ports,
                    :thunk_id_to_ractorized_object_id,
                    :return_value_port_created_in_ractor

      def initialize
        self.ractorized_object_id_to_ractor = {}
        self.ractorized_object_id_to_return_ports = {}
        self.thunk_id_to_ractorized_object_id = {}
        self.return_value_port_created_in_ractor = ObjectSpace::WeakMap.new
      end

      def put_ractor(ractorized_object_id, ractor)
        ractorized_object_id_to_ractor[ractorized_object_id] = ractor
      end

      def get_ractor(ractorized_object_id)
        ractorized_object_id_to_ractor[ractorized_object_id]
      end

      def delete_ractor(ractorized_object_id)
        ractorized_object_id_to_ractor.delete(ractorized_object_id)
      end

      def construct_ractorized_object(...)
        ractorized_object = RactorizedObject.new(...)

        setup_ractorized_object_finalizer(ractorized_object)

        ::Object.instance_method(:freeze).bind_call(ractorized_object)

        ractorized_object
      end

      def construct_thunk(ractorized_object_id, return_value_port, created_in_ractor)
        thunk = Thunk.new(return_value_port)

        thunk_id = thunk.__object_id__

        thunk_id_to_ractorized_object_id[thunk_id] = ractorized_object_id

        return_value_port_created_in_ractor[return_value_port] = created_in_ractor

        return_ports = ractorized_object_id_to_return_ports[ractorized_object_id] ||= ObjectSpace::WeakMap.new
        return_ports[thunk_id] = return_value_port

        puts "ractorized_object_id_to_return_ports[#{ractorized_object_id}][#{thunk_id}] = #{return_value_port} "

        pp ractorized_object_id_to_return_ports
        setup_thunk_finalizer(thunk)

        ::Object.instance_method(:freeze).bind_call(thunk)

        thunk
      end

      def clean_up_after_ractorized_object(ractorized_object_id)
        puts "cleaning up after #{ractorized_object_id} yay!!!"
        ractor = ractorized_object_id_to_ractor.delete(ractorized_object_id)

        unless ractor
          raise "wtf no ractor??"
        end

        if ractor
          thunk_id_to_port = ractorized_object_id_to_return_ports.delete(ractorized_object_id)

          puts "here's thunk_id_to_port:"
          pp thunk_id_to_port

          ports = thunk_id_to_port&.values

          if ports&.any?
            puts "Going to clean up ports!! yaaaaay!"
            ractor_to_ports = ports.group_by do |port|
              return_value_port_created_in_ractor[port]
            end

            ractor_to_ports.each_pair do |ractor, ports|
              ractor&.send([:close_ports, ports.freeze].freeze)
            rescue Ractor::ClosedError
              # do nothing
            end
          else
            puts "hmmmm no ports to clean up??"
          end

          begin
            ractor << :__close__
          rescue Ractor::ClosedError
            # do nothing
          end
        end
      end

      def clean_up_after_thunk(thunk_id)
        puts "in cleanup after thunk:"
        pp ractorized_object_id_to_return_ports

        ractorized_object_id = thunk_id_to_ractorized_object_id.delete(thunk_id)
        port = ractorized_object_id_to_return_ports[ractorized_object_id]&.delete(thunk_id)

        if port
          created_in_ractor = return_value_port_created_in_ractor[port]

          if created_in_ractor
            if created_in_ractor == Ractor.current
              port.close
            elsif created_in_ractor.is_a?(RactorizedObject::RactorizedRactor)
              begin
                puts "closing port in thunk cleanup!! #{port}"
                ractor << [:__close_port__, port].freeze
              rescue Ractor::ClosedError
                # do nothing
              end
            end
          else
            puts "whoa, why no created in ractor when cleaning up thunk??"
          end
        else
          puts "whoa why no port in cleanup ractor?"
        end
      end

      private

      def ractorized_object_finalize_proc
        proc do |ractorized_object_id|
          puts "finalizer called for #{ractorized_object_id}!!! #{Ractor.current}"

          begin
            TRACKING_RACTOR << [:clean_up_after_ractorized_object, ractorized_object_id].freeze
          rescue Ractor::ClosedError
            # do nothing
          end
        rescue => e
          puts e
          puts e.backtrace
          puts "wtf????"
          raise "caboom!!!"
        end
      end

      def setup_ractorized_object_finalizer(ractorized_object)
        ObjectSpace.define_finalizer(ractorized_object, &ractorized_object_finalize_proc)
      end

      def thunk_finalize_proc
        proc do |thunk_id|
          puts "thunk finalizer called for #{thunk_id}!!! #{Ractor.current}"

          begin
            TRACKING_RACTOR << [:clean_up_after_thunk, thunk_id].freeze
          rescue Ractor::ClosedError
            # do nothing
          end
        end
      end

      def setup_thunk_finalizer(thunk)
        ObjectSpace.define_finalizer(thunk, &thunk_finalize_proc)
      end
    end
  end
end
