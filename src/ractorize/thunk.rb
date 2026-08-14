module Ractorize
  class Thunk < BasicObject
    class EscapingRactorError < ::StandardError; end

    attr_accessor :__thunk_ractor__, :__object_id__

    def initialize(return_value_ractor)
      self.__thunk_ractor__ = return_value_ractor
      self.__object_id__ = ::Object.instance_method(:object_id).bind_call(self)
      ::Ractorize::GarbageCollection.track_thunk(self)
    end

    def initialize_clone(original_thunk)
      if __resolved__? && original_thunk.__resolved__?
        # Seems this could happen if we had a frozen thunk whose @__value__ is not shareable
        # Since the thunk's ractor is already gone nothing to worry about
        return
      end

      self.__object_id__ = ::Object.instance_method(:object_id).bind_call(self)

      ::Ractorize::GarbageCollection.thunk_cloned(original_thunk, self)
    end

    def __resolved__? = defined?(@__value__)

    def method_missing(...)
      __value__.__send__(...)
    end

    def respond_to_missing?(method_name, include_all = false)
      __value__.respond_to?(method_name, include_all)
    end

    def __value__
      return @__value__ if defined?(@__value__)

      @__value__ = __thunk_ractor__.join.value
      self.__thunk_ractor__ = nil
      ::Object.instance_method(:freeze).bind_call(self)

      @__value__
    end

    def ! = !__value__
    def ==(other) = __value__ == other || super
    def !=(other) = __value__ != other || super
    def equal?(other) = __value__.equal?(other) || super
  end
end
