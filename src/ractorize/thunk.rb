# require "weakref"

module Ractorize
  class Thunk < BasicObject
    class << self
      def setup_finalizer(garbage_collectable) # , port)
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
      garbage_collectable = ::Object.new

      ::Kernel.puts "setting up finalizer..."
      # ::Ractorize::Thunk.setup_finalizer(garbage_collectable) # , return_value_port)

      # garbage_collectable.freeze
      @__garbage_collectable__ = garbage_collectable
    end

    def initialize_clone(...)
      # is this actually necessary?? Seems so?
    end

    def method_missing(...)
      __value__.__send__(...)
    end

    def respond_to_missing?(method_name, include_all = false)
      __value__.respond_to?(method_name, include_all)
    end

    def resolved? = !!defined?(@__value__)

    def __value__
      return @__value__ if defined?(@__value__)

      value = # if ::Ractor.current == __ractor__
        __return_value_port__.receive
      # else
      #   # :nocov:
      #   ::Kernel.raise EscapingRactorError,
      #                  "Somehow this thunk was passed between ractors but wasn't resolved first."
      #   # :nocov:
      # end

      # :nocov:
      ::Kernel.raise EscapingRactorError if ::Ractorize::Thunk === value
      # :nocov:

      @__value__ = value
      self.__ractor__ = nil
      __return_value_port__.close
      self.__return_value_port__ = nil

      ::Object.instance_method(:freeze).bind(self).call

      value
    end

    def ! = !__value__
    def ==(other) = __value__ == other || super
    def !=(other) = __value__ != other || super
    def equal?(other) = __value__.equal?(other) || super
  end
end
