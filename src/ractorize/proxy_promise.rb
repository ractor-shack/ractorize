class Ractorize < BasicObject
  class ProxyPromise < BasicObject
    attr_accessor :__return_value_port__

    def initialize(return_value_port)
      self.__return_value_port__ = return_value_port
    end

    def method_missing(method_name, *)
      __value__.send(method_name, *)
    end

    def respond_to_missing?(method_name, include_all = false)
      __value__.respond_to?(method_name, include_all)
    end

    def __value__
      return @__value__ if defined?(@__value__)

      @__value__ = __return_value_port__.receive
    end

    def !
      !__value__
    end

    def ==(other)
      __value__ == other || super
    end
  end
end
