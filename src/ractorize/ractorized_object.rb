# TODO: make use of autoload?
require_relative "thunk"

module Ractorize
  class RactorizedObject < BasicObject
    class RactorizedRactor < ::Ractor; end

    attr_reader :__object_id__, :__ractor__

    def initialize(mode, *args, **opts, &block)
      @__ractor__ = RactorizedRactor.new(name: "#{args.first}<#{args.first.object_id}>", &RACTOR_PROC)

      case mode
      when :object
        @__ractor__ << :object

        outside_object = args.first

        @__target_class__ = outside_object.class

        if ::Ractor.shareable?(outside_object)
          @__ractor__ << outside_object
        else
          ::Ractorize.resolve_all_thunks(outside_object)
          @__ractor__.send(outside_object, move: true)
        end
      when :class
        klass, *args = args

        @__target_class__ = klass

        to_move = ::Ractorize.prepare_args(@__target_class__, args, opts)

        if to_move&.any?
          @__ractor__ << :class_arg_by_arg
          @__ractor__ << klass

          args.each do |arg|
            @__ractor__ << :arg
            @__ractor__.send(arg, move: to_move.include?(arg))
          end

          opts.each_pair do |name, value|
            @__ractor__ << :kwarg
            @__ractor__ << name
            @__ractor__.send(value, move: to_move.include?(value))
          end

          if block
            @__ractor__ << :block
            @__ractor__ << block
          end

          @__ractor__ << :done
        else
          @__ractor__ << :class
          @__ractor__ << [klass, args.freeze, opts.dup.freeze, block].freeze
        end
      else
        # :nocov:
        ::Kernel.raise "Invalid mode #{mode}"
        # :nocov:
      end

      @__object_id__ = ::Object.instance_method(:object_id).bind_call(self)

      ::Ractorize::GarbageCollection.track_ractorized_object(self)
    end

    def __close__ = method_missing(:__close__)

    def __join__
      __close__
      @__ractor__.join
      self
    end

    def method_missing(method_name, *args, **opts, &block)
      if @__ractor__.default_port.closed?
        ::Kernel.raise ::Ractor::ClosedError,
                       "You already closed this Ractorized instance of #{@__target_class__}!\n" \
                       "No more methods can be sent to it but you sent #{method_name}"
      end

      return_port = ::Ractor::Port.new

      to_move = ::Ractorize.prepare_args(@__target_class__, args, opts)

      if to_move&.any?
        @__ractor__ << [:__invoke_arg_by_arg__, [].freeze, {}.freeze, return_port, !!block]

        args_port = return_port.receive
        args_port << method_name

        args.each do |arg|
          args_port << :arg
          args_port.send(arg, move: to_move.include?(arg))
        end

        opts.each_pair do |name, value|
          args_port << :kwarg
          args_port << name
          args_port.send(value, move: to_move.include?(value))
        end

        args_port << :done
      else
        @__ractor__ << [method_name, args.dup.freeze, opts.dup.freeze, return_port, !!block].freeze
      end

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
            method_name == :inspect || method_name == :to_s ||
            method_name.end_with?("?") || method_name == :hash
        thunk_ractor = return_port.receive
        value = thunk_ractor.join.value

        # :nocov:
        ::Kernel.raise ::Ractorize::Thunk::EscapingRactorError if ::Ractorize::Thunk === value
        # :nocov:

        value
      else
        Thunk.new(return_port.receive)
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

    def ==(other) = method_missing(:==, other) || super
    def !=(other) = method_missing(:==, other) || super
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
