module Ractorize
  module GarbageCollection
    class RactorizedTracker
      attr_accessor :ractorized_object_id_to_ractor,
                    :ractorized_object_id_to_return_ports,
                    :thunk_id_to_ractorized_object_id

      def initialize
        self.ractorized_object_id_to_ractor = {}
        self.ractorized_object_id_to_return_ports = {}
        self.thunk_id_to_ractorized_object_id = {}
      end

      def put_ractor(ractorized_object_id, ractor)
        ractorized_object_id_to_ractor[ractorized_object_id] = ractor
      end

      def get_ractor(ractorized_object_id)
        puts "getting the ractor for ractorized object #{ractorized_object_id}"
        puts "the map is:"
        pp ractorized_object_id_to_ractor
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

      def construct_thunk(ractorized_object_id, return_value_port)
        thunk = Thunk.new(return_value_port)

        thunk_id = thunk.__object_id__

        return_ports = ractorized_object_id_to_return_ports[ractorized_object_id] ||= ObjectSpace::WeakMap.new
        return_ports[thunk_id] = return_value_port

        thunk_id_to_ractorized_object_id[thunk_id] = ractorized_object_id

        setup_thunk_finalizer(thunk)

        ::Object.instance_method(:freeze).bind_call(thunk)

        thunk
      end

      def clean_up_after_ractorized_object(ractorized_object_id)
        ractor = ractorized_object_id_to_ractor.delete(ractorized_object_id)

        if ractor
          thunk_id_to_port = ractorized_object_id_to_return_ports.delete(ractorized_object_id)

          ports = thunk_id_to_port.values

          ractor << if ports&.any?
                      [:__abandon_ports_and_close__, [ports].freeze].freeze
                    else
                      :__close__
                    end rescue Ractor::ClosedError
        end
      end

      def clean_up_after_thunk(thunk_id)
        ractorized_object_id = thunk_id_to_ractorized_object_id.delete(thunk_id)
        ractor = ractorized_object_id_to_ractor[ractorized_object_id]
        port = ractorized_object_id_to_return_ports[ractorized_object_id]&.delete(thunk_id)

        if ractor
          if port
            ractor << [:__close_port__, port].freeze rescue Ractor::ClosedError
          end
        end
      end

      private

      def ractorized_object_finalize_proc
        proc do |ractorized_object_id|
          puts "finalizer called for #{ractorized_object_id}!!!"
          # self.class.instance.clean_up_after_ractorized_object(ractorized_object_id)
          TRACKING_RACTOR << [:clean_up_after_ractorized_object, ractorized_object_id].freeze rescue Ractor::ClosedError
        end
      end

      def setup_ractorized_object_finalizer(ractorized_object)
        ObjectSpace.define_finalizer(ractorized_object, &ractorized_object_finalize_proc)
      end

      def thunk_finalize_proc
        proc do |thunk_id|
          puts "thunk finalizer called for #{thunk_id}!!!"
          TRACKING_RACTOR << [:clean_up_after_thunk, thunk_id].freeze rescue Ractor::ClosedError
        end
      end

      def setup_thunk_finalizer(thunk)
        ObjectSpace.define_finalizer(thunk, &thunk_finalize_proc)
      end
    end
  end
end
