module Ractorize
  class Thunk < BasicObject
    class ThunkRactor < ::Ractor
      class << self
        def new
          super do
            case receive
            in :__close__
              raise ::Ractor::ClosedError
            in :success, value
            end

            value
          end
        end
      end
    end

    class EscapingRactorError < ::StandardError; end

    attr_accessor :__return_value_portlike__

    def initialize(return_value_portlike)
      self.__return_value_portlike__ = return_value_portlike

    end

    def initialize_clone(...)
      puts "CAREFUL! THUNK CLONED!!"
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

      @__value__ = __return_value_portlike__.join.value
      self.__return_value_portlike__ = nil
      ::Object.instance_method(:freeze).bind_call(self)

      @__value__
    end

    def ! = !__value__
    def ==(other) = __value__ == other || super
    def !=(other) = __value__ != other || super
    def equal?(other) = __value__.equal?(other) || super
  end
end
