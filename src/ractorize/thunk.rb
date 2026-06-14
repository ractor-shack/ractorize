# require "weakref"

module Ractorize
  class Thunk < BasicObject
    class EscapingRactorError < ::StandardError; end

    attr_accessor :__return_value_port__, :__ractor__, :because_of_class, :because_of_method
    attr_reader :__object_id__

    def initialize(return_value_port)
      # self.__ractor__ = ::Ractor.current
      self.because_of_class = because_of_class
      self.because_of_method = because_of_method

      self.__return_value_port__ = return_value_port
      @__return_port_object_id__ = return_value_port.object_id

      @__object_id__ = ::Object.instance_method(:object_id).bind_call(self)
      ::Kernel.puts "making thunk <#{@__object_id__}> for port #{return_value_port}"

      # ::Object.instance_method(:freeze).bind_call(self)
    end

    def initialize_clone(...)
      raise "whoa!"
      # is this actually necessary?? Seems so?
    end

    def method_missing(method_name, ...)
      __value__.__send__(method_name, ...)
    end

    def respond_to_missing?(method_name, include_all = false)
      __value__.respond_to?(method_name, include_all)
    end

    def resolved? = !!defined?(@__resolving_ractor__)

    def abandon!
      __return_value_port__&.close rescue Ractor::ClosedError
    end

    def __value__
      return @__value__ if defined?(@__value__)

      puts "resolving thunk!!"
      port = ::Ractorize::GarbageCollection.portlike_for(@__return_port_object_id__)
      @__value__ = begin
        ::Kernel.raise "wtf" unless port

        port.receive
      ensure
        port.close
        ::Ractorize::GarbageCollection.untrack(self, port)
      end

      ::Object.instance_method(:freeze).bind_call(self)

      @__value__
    end

    def ! = !__value__
    def ==(other) = __value__ == other || super
    def !=(other) = __value__ != other || super
    # def eql?(other) = method_missing(:eql?, other) || super
    # def equal?(other) = __value__.equal?(other) || super
  end
end
