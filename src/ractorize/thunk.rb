# require "weakref"

module Ractorize
  class Thunk < BasicObject
    class << self
      def setup_finalizer(garbage_collectable)
        # port_ref = WeakRef.new(port)

        ::ObjectSpace.define_finalizer(garbage_collectable) do |id|
          ::Kernel.puts "finalizing a thunk with object id #{id}!"
          # port_ref.close
        end
      end
    end

    class EscapingRactorError < ::StandardError; end

    attr_accessor :__return_value_port__, :__ractor__

    def initialize(return_value_port)
      # self.__ractor__ = ::Ractor.current
      self.__return_value_port__ = return_value_port
      # garbage_collectable = ::Object.new

      # ::Ractorize::Thunk.setup_finalizer(self) # , return_value_port)

      # garbage_collectable.freeze
      # @__garbage_collectable__ = garbage_collectable
    end

    def initialize_clone(...)
      # is this actually necessary?? Seems so?
    end

    def method_missing(...)
      __value__.__send__(...)
    end

    def abandoned!
      ::Kernel.puts "aandoned!"
      unless defined?(@__resolving_ractor__)
        ::Kernel.puts "closing in abandoned!!"
      end
      __return_value_port__&.close
      @__resolving_ractor__&.<<(:close)
      @__resolving_ractor__ = nil
    end

    def respond_to_missing?(method_name, include_all = false)
      __value__.respond_to?(method_name, include_all)
    end

    def resolved? = !!defined?(@__resolving_ractor__)

    def __value__
      return @__value__ if defined?(@__value__)

      @__value__ = __resolving_ractor__.join.value

      @__resolving_ractor__ = nil

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
        value = nil

        ::Kernel.loop do
          action = receive

          case action
          when :close
            close
          when :value
            value = receive
            break
          else
            ::Kernel.raise "Not sure what to do with #{action}"
          end
        rescue => e
          ::Kernel.raise "wtf didn't handle #{e} in resolving ractor"
        end

        value
      end

      start_resolving_ractor(__return_value_port__)

      self.__return_value_port__ = nil

      # ::Object.instance_method(:freeze).bind(self).call

      @__resolving_ractor__
    end

    def start_resolving_ractor(p)
      ::Thread.new do
        @__resolving_ractor__ << :value
        @__resolving_ractor__ << p.receive
        @__resolving_ractor__ << :close
        p.close
        nil
      end
    end

    def ! = !__value__
    def ==(other) = __value__ == other || super
    def !=(other) = __value__ != other || super
    def equal?(other) = __value__.equal?(other) || super
  end
end
