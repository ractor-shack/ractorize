# require "weakref"

module Ractorize
  class Thunk < BasicObject
    class << self
      def store_port(thunk_id, port)
        thunk_id_to_port = Ractor[:thunk_id_to_port] ||= ObjectSpace::WeakMap.new
        thunk_id_to_port[thunk_id] = port
      end

      def port_for(thunk_id)
        Ractor[:thunk_id_to_port]&.[](thunk_id)
      end

      def remove_port_for(thunk_id)
        Ractor[:thunk_id_to_port]&.delete(thunk_id)
      end

      def finalizer_proc(thunk_id)
        proc do |id|
          port = remove_port_for(thunk_id)
          puts "closing #{port} in thunk finalizer for #{id} thunk_id #{thunk_id}"
          port&.close
        rescue => e
          puts "wtf unhandled in thunk finalizer: #{e}"
          puts e.backtrace
        end
      end

      def setup_finalizer_proc(created_for_class, created_for_method)
        proc do |id|
          puts "finalizing a thunk with #{id} from #{created_for_class}##{created_for_method}"

          thunks = Ractor[:thunks]

          if thunks
            port = thunks[id]
            if port
              puts "found port yaaaaaaaaay!!! #{port}"

              if port.closed?
                puts "already closed so doing nothing"
              else
                begin
                  puts "closing the port"
                  port.close
                rescue Ractor::ClosedError
                  puts "closed error while closing port"
                end
                # ractor.join
                # ::Ractorize::RactorizedObject.abandon_thunks(id)
              end
            else
              puts "hmmm no ractor found in finalizer??"
            end
          end
        end
      end

      def setup_finalizer(thunk, port, klass, method)
        # port_ref = WeakRef.new(port)
        thunks = Ractor[:thunks] ||= ObjectSpace::WeakMap.new

        thunks[thunk.__thunk_id__] = port
        ObjectSpace.define_finalizer(thunk, &setup_finalizer_proc(klass, method))
      end
    end

    class EscapingRactorError < ::StandardError; end

    attr_accessor :__return_value_port__, :__ractor__, :because_of_class, :because_of_method
    attr_reader :__thunk_id__

    def initialize(return_value_port, because_of_class, because_of_method)
      # self.__ractor__ = ::Ractor.current
      self.because_of_class = because_of_class
      self.because_of_method = because_of_method

      # self.__return_value_port__ = return_value_port

      @__thunk_id__ = ::Object.instance_method(:object_id).bind_call(self)
      ::Ractorize::Thunk.store_port(@__thunk_id__, return_value_port)

      ::Ractorize::Thunk.setup_finalizer(self, return_value_port, because_of_class, because_of_method)

      # garbage_collectable.freeze
      # @__garbage_collectable__ = garbage_collectable
    end

    def initialize_clone(...)
      # is this actually necessary?? Seems so?
    end

    def method_missing(method_name, ...)
      ::Kernel.puts "thunk method missing handling #{method_name}"
      __value__.__send__(method_name, ...)
    end

    def abandon!
      ::Kernel.puts "aandoned!"

      unless defined?(@__resolving_ractor__)
        ::Kernel.puts "closing in abandoned!!"
      end
      if __return_value_port__
        ::Kernel.puts "abandoning and port is present, so closing it!"
        begin
          __return_value_port__.close
        rescue Ractor::ClosedError
          # do nothing
        end
        self.__return_value_port__ = nil
      end

      if @__resolving_ractor__
        @__resolving_ractor__ << :close
        @__resolving_ractor__ = nil
      end

      nil
    end

    def respond_to_missing?(method_name, include_all = false)
      __value__.respond_to?(method_name, include_all)
    end

    def resolved? = !!defined?(@__resolving_ractor__)

    def __value__
      ::Kernel.puts "uh oh, __value__ called hmm..."
      return @__value__ if defined?(@__value__)

      port = ::Ractorize::Thunk.port_for(@__thunk_id__)
      @__value__ = begin
        ::Kernel.raise "wtf" unless port

        port.receive
      ensure
        port.close
        ::Ractorize::Thunk.remove_port_for(@__thunk_id__)
      end

      return @__value__

      @__value__ = __return_value_port__.receive

      @__resolving_ractor__ = nil
      self.__ractor__ = nil
      __return_value_port__&.close
      self.__return_value_port__ = nil

      ::Object.instance_method(:freeze).bind(self).call

      return @__value__
      #
      # ::Kernel.puts "calling receive on the port... #{__return_value_port__}"
      # value = # if ::Ractor.current == __ractor__
      #   __return_value_port__.receive
      # ::Kernel.puts "value received... #{__return_value_port__}"
      #
      # # else
      #   # :nocov:
      #   ::Kernel.raise EscapingRactorError,
      #                  "Somehow this thunk was passed between ractors but wasn't resolved first."
      #   # :nocov:
      # end

      # :nocov:
      # ::Kernel.raise EscapingRactorError if ::Ractorize::Thunk === value
      # :nocov:

      @__value__ = value
      self.__ractor__ = nil
      __return_value_port__.close
      self.__return_value_port__ = nil

      ::Object.instance_method(:freeze).bind(self).call

      value
    end

    def __resolving_ractor__
      return @__resolving_ractor__ if defined?(@__resolving_ractor__)

      @__resolving_ractor__ = ::Ractor.new do
        action, value = receive

        unless action == :close || action == :value
          ::Kernel.raise "Not sure what to do with #{action}"
        end

        value
      rescue => e
        ::Kernel.raise "wtf didn't handle #{e} in resolving ractor"
      end

      start_resolving_ractor(__return_value_port__)

      self.__return_value_port__ = nil

      # ::Object.instance_method(:freeze).bind(self).call

      @__resolving_ractor__
    end

    def start_resolving_ractor(p)
      ::Thread.new do
        begin
          @__resolving_ractor__ << [:value, p.receive].freeze
        rescue ::Ractor::ClosedError
          # do nothing
        end
        begin
          p.close
        rescue ::Ractor::ClosedError
          # do nothing
        end
        nil
      end
    end

    def ! = !__value__
    def ==(other) = __value__ == other || super
    def !=(other) = __value__ != other || super
    # def eql?(other) = method_missing(:eql?, other) || super
    # def equal?(other) = __value__.equal?(other) || super
  end
end
