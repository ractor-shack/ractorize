# TODO: make use of autoload?
require_relative "thunk"

module Ractorize
  class RactorizedObject < BasicObject
    def initialize(outside_object)
      @ractor = ::Ractor.new(&RACTOR_PROC)

      # It doesn't seem like we have a way to move the object into the ractor via its constructor so do
      # it with #<< instead.
      if ::Ractor.shareable?(outside_object)
        @ractor << outside_object
      else
        @ractor.send(outside_object, move: true)
      end

      # Wow, this works! Scary?
      ::Object.instance_method(:freeze).bind(self).call
    end

    def __close__ = method_missing(:__close__)

    def __join__
      __close__
      @ractor.join
      self
    end

    def method_missing(method_name, *args, **opts, &block)
      if block
        ::Kernel.raise "Does not currently support passing blocks to methods of ractorized objects!"
      end

      if @ractor.default_port.closed?
        ::Kernel.raise ::Ractor::ClosedError,
                       "You already closed this Ractorized object! No more methods can be sent to it."
      end

      return_port = ::Ractor::Port.new

      @ractor << [method_name, args.dup.freeze, opts.dup.freeze, return_port].freeze

      # Let's assume the user would rather block on all predicate methods than
      # incorrectly get a non-truthy value (thunk is always truthy even if it evaluates as nil/false)
      if method_name == :== || method_name == :! || method_name == :!= || method_name.end_with?("?")
        return_port.receive
      else
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
      method_missing(:respond_to?, method_name, include_all)
    end

    def ==(other) = method_missing(:==, other)
    def !=(other) = method_missing(:==, other)
    def ! = method_missing(:!)
    def equal?(other) = method_missing(:equal?, other)

    def to_s = inspect

    def inspect
      "RactorizedObject<#{::Object.instance_method(:object_id).bind(self).call}>[#{method_missing(:inspect)}]".freeze
    end
  end
end
