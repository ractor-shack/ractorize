# TODO: make use of autoload?
require_relative "thunk"

module Ractorize
  class RactorizedObject < BasicObject
    # Putting this in a constant so we can get test coverage on it since not sure how to get coverage
    # on something inside a ractor.

    attr_accessor :__object__

    def initialize(outside_object)
      @ractor = ::Ractor.new(&RACTOR_PROC)

      # It doesn't seem like we have a way to move the object into the ractor via its constructor so do
      # it with #<< instead.
      @ractor.<<(outside_object, move: true)
    end

    def close
      result = method_missing(:close)

      @__object__ = if Thunk === result
                      result.__value__
                    else
                      result
                    end
    end

    def join
      close
      @ractor.join
      self
    end

    def method_missing(method_name, *args, **opts)
      return @__object__ if method_name == :close && @ractor.default_port.closed?

      if defined?(@__object__)
        @__object__.__send__(method_name, *args, **opts)
      else
        return_port = ::Ractor::Port.new

        @ractor << [method_name, args, opts, return_port]

        Thunk.new(return_port)
      end
    end

    def respond_to?(method_name, include_all = false)
      # :nocov:
      # This line is only here for when commenting out < BasicObject when debugging stuff
      return super if ::Object === self
      # :nocov:

      respond_to_missing?(method_name, include_all)
    end

    def respond_to_missing?(method_name, include_all = false)
      value = method_missing(:respond_to?, method_name, include_all)

      if ::Ractorize::Thunk === value
        value.__value__
      else
        value
      end
    end
  end
end
