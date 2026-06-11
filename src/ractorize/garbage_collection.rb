module Ractorize
  module GarbageCollection
    class << self
      def finalize_proc
        @finalize_proc ||= proc do |id|
          puts "going to clean up!! #{id}"
          GarbageCollection.cleanup_ractor << [:clean_up, id].freeze
        rescue Ractor::ClosedError
          puts "hmmm cleanup ractor already closed??"
        end
      end

      def track_ractorized_object(ractorized_object)
        cleanup_ractor << [:add]
      end

      def cleanup_ractor
        @cleanup_ractor ||= Ractor.new do
          id_to_portlike = ObjectSpace::WeakMap.new

          loop do
            action, object_or_id, port_like = receive

            case action
            when :add
              id_to_portlike[object_or_id.object_id] = port_like
              port_like = nil
              ObjectSpace.define_finalizer(object_or_id, &finalize_proc)
              object_or_id = nil
            when :clean_up
              puts "going to cleanup #{object_or_id}!"
              port_like = id_to_portlike[object_or_id]

              if port_like
                puts "it has port-like #{port_like}"
                begin
                  puts "attempting close!"
                  port_like << :__close__
                  puts "worked!"
                rescue Ractor::ClosedError
                  puts "failed to close! already closed??"
                end
                port_like = nil
              else
                puts "it has no port-like"
              end
            when :close
              close
              break
            else
              raise "wtf, can't handle #{action}"
            end
          end

          nil
        end
      end
    end
  end
end
