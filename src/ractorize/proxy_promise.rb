#!/usr/bin/env ruby

class Ractorize
  class ProxyPromise < BasicObject
    attr_accessor :__target__, :__resolved__, :__value__

    def initialize(__target__)
      self.__target__ = __target__
    end

    def method_missing(method_name, *)
      unless __resolved__
        self.__value__ = __target__.receive
        self.__resolved__ = true
      end

      __value__.send(method_name, *)
    end
  end
end
