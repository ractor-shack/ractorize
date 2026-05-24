module Ractorize
  class Thunk < BasicObject
    class EscapingRactorError < ::StandardError; end

    attr_accessor :__return_value_port__, :__ractor__

    def initialize(return_value_port)
      self.__ractor__ = ::Ractor.current
      self.__return_value_port__ = return_value_port
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

    def __value__
      return @__value__ if defined?(@__value__)

      value = if ::Ractor.current == __ractor__
                __return_value_port__.receive
              else
                # :nocov:
                raise "Somehow this thunk was passed between ractors but wasn't resolved first."
                # :nocov:
              end

      # :nocov:
      ::Kernel.raise EscapingRactorError if ::Ractorize::Thunk === value
      # :nocov:

      @__value__ = value

      ::Object.instance_method(:freeze).bind(self).call

      value
    end

    def !
      !__value__
    end

    def ==(other)
      __value__ == other || super
    end
  end
end
