class Ractorize
  class ProxyPromise < BasicObject
    attr_accessor :__target__, :__resolved__, :__value__

    def initialize(target)
      self.__target__ = target
    end

    def method_missing(method_name, *)
      unless __resolved__
        self.__value__ = __target__.receive
        self.__resolved__ = true
      end

      __value__.send(method_name, *)
    end

    def respond_to_missing?(method_name, include_all = false)
      unless __resolved__
        self.__value__ = __target__.receive
        self.__resolved__ = true
      end

      __value__.respond_to?(method_name, include_all)
    end
  end
end
