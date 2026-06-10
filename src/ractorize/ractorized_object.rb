# TODO: make use of autoload?
require_relative "thunk"

module Ractorize
  class RactorizedObject < BasicObject
    class << self
      def setup_finalizer_proc(ractor)
        proc do
          ractor << :__close__ unless ractor.default_port.closed?
        rescue Ractor::ClosedError
          # intentionally swallowing this up
        end
      end

      def setup_finalizer(ractorized_object, ractor)
        ObjectSpace.define_finalizer(ractorized_object, &setup_finalizer_proc(ractor))
      end
    end

    def initialize(mode, *args, **opts, &block)
      @ractor = ::Ractor.new(name: "#{args.first}<#{args.first.object_id}>", &RACTOR_PROC)
      RactorizedObject.setup_finalizer(self, @ractor)

      case mode
      when :object
        @ractor << :object

        outside_object = args.first

        @__target_class__ = outside_object.class

        if ::Ractor.shareable?(outside_object)
          @ractor << outside_object
        else
          ::Ractorize.resolve_all_thunks(outside_object)
          @ractor.send(outside_object, move: true)
        end
      when :class
        klass, *args = args

        @__target_class__ = klass

        to_move = ::Ractorize.prepare_args(@__target_class__, args, opts)

        if to_move&.any?
          @ractor << :class_arg_by_arg
          @ractor << klass

          args.each do |arg|
            @ractor << :arg
            @ractor.send(arg, move: to_move.include?(arg))
          end

          opts.each_pair do |name, value|
            @ractor << :kwarg
            @ractor << name
            @ractor.send(value, move: to_move.include?(value))
          end

          if block
            @ractor << :block
            @ractor << block
          end

          @ractor << :done
        else
          @ractor << :class
          @ractor << [klass, args.freeze, opts.dup.freeze, block].freeze
        end
      else
        # :nocov:
        ::Kernel.raise "Invalid mode #{mode}"
        # :nocov:
      end

      ::Object.instance_method(:freeze).bind(self).call
    end

    def __close__
      # if @ractor.default_port.closed?
      #   @ractor.value
      # else
      # hmmm can't undefine this on self since we are frozen.
      # Do we really need to freeze our self? We won't be shareable if we're not frozen ugg.
      # ::ObjectSpace.undefine_finalizer(self)
      method_missing(:__close__)
      #       end
    end

    def __join__
      object = __close__
      @ractor.join
      object.__value__
    end

    def method_missing(method_name, *args, **opts, &block)
      if @ractor.default_port.closed? # && method_name != :__close__ && method_name != :__join__
        ::Kernel.raise ::Ractor::ClosedError,
                       "You already closed this Ractorized instance of #{@__target_class__}!\n" \
                       "No more methods can be sent to it but you sent #{method_name}"
      end

      return_port = ::Ractor::Port.new

      to_move = ::Ractorize.prepare_args(@__target_class__, args, opts)

      if to_move&.any?
        @ractor << [:__invoke_arg_by_arg__, [].freeze, {}.freeze, return_port, !!block]

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
        @ractor << [method_name, args.dup.freeze, opts.dup.freeze, return_port, !!block].freeze
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

        return_port.close

        value
      # Let's assume the user would rather block on all predicate methods than
      # incorrectly get a non-truthy value (thunk is always truthy even if it evaluates as nil/false)
      elsif method_name == :== || method_name == :! || method_name == :!= ||
            method_name == :inspect || method_name == :to_s || method_name.end_with?("?")
        value = return_port.receive

        return_port.close
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
      moved_object_inspect = if @ractor.default_port.closed?
                               ::Object.instance_method(:object_id).bind_call(self)
                             else
                               method_missing(:inspect)
                             end

      "RactorizedObject<#{object_id}>[#{moved_object_inspect}]".freeze
    end
  end
end
