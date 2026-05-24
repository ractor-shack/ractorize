# TODO: make use of autoload?
require_relative "thunk"

module Ractorize
  class RactorizedObject < BasicObject
    def initialize(mode, *args, **opts, &block)
      @ractor = ::Ractor.new(&RACTOR_PROC)

      case mode
      when :object
        @ractor << :object

        outside_object = args.first

        ::Ractorize.resolve_all_thunks(outside_object)

        if ::Ractor.shareable?(outside_object)
          @ractor << outside_object
        else
          @ractor.send(outside_object, move: true)
        end
      when :class
        @ractor << :class

        klass, *args = args

        ::Ractorize.resolve_all_thunks(args)
        ::Ractorize.resolve_all_thunks(opts)

        @ractor << [klass, args.freeze, opts.dup.freeze, block].freeze
      else
        # :nocov:
        ::Kernel.raise "Invalid mode #{mode}"
        # :nocov:
      end

      ::Object.instance_method(:freeze).bind(self).call
    end

    def __close__ = method_missing(:__close__)

    def __join__
      __close__
      @ractor.join
      self
    end

    def method_missing(method_name, *args, **opts, &block)
      if @ractor.default_port.closed?
        ::Kernel.raise ::Ractor::ClosedError,
                       "You already closed this Ractorized object! No more methods can be sent to it."
      end

      return_port = ::Ractor::Port.new

      ::Ractorize.resolve_all_thunks(args)
      ::Ractorize.resolve_all_thunks(opts)

      @ractor << [method_name, args.dup.freeze, opts.dup.freeze, return_port, !!block].freeze

      if block
        stop = false
        value = nil

        until stop
          data = return_port.receive

          # Seems SimpleCov branch coverage doesn't like that we don't test the non-exhaustive
          # pattern path, but since that's purely defensive I have no interest in testing it.

          # :nocov:
          case data
          # :nocov:
          in :return, value
            stop = true
          in :yield, [yielded_args, yielded_opts, yielded_block], block_result_port
            # TODO: yielded_block likely won't work when actually used
            # so we should probably instead just raise an exception
            # TODO: handle break and also raise in the block
            block_result = block.call(*yielded_args.freeze, **yielded_opts.freeze, &yielded_block)

            block_result = block_result.__value__ while ::Ractorize::Thunk === block_result

            block_result_port << [:normal, block_result].freeze
          end
        end

        value
      # Let's assume the user would rather block on all predicate methods than
      # incorrectly get a non-truthy value (thunk is always truthy even if it evaluates as nil/false)
      elsif method_name == :== || method_name == :! || method_name == :!= ||
            method_name == :inspect || method_name == :to_s || method_name.end_with?("?")
        value = return_port.receive

        # :nocov:
        ::Kernel.raise ::Ractorize::Thunk::EscapingRactorError if ::Ractorize::Thunk === value
        # :nocov:

        value
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
      object_id = ::Object.instance_method(:object_id).bind(self).call
      moved_object_inspect = method_missing(:inspect)

      "RactorizedObject<#{object_id}>[#{moved_object_inspect}]".freeze
    end
  end
end
