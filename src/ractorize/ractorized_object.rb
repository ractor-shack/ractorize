# TODO: make use of autoload?
require_relative "thunk"

module Ractorize
  class RactorizedObject < BasicObject
    class RactorizedRactor < ::Ractor; end

    def initialize(mode, *args, **opts, &block)
      # A bit of a hack here... We can't get a handle on the ractor at first due to a deadlock.
      ractor = ::Ractorize::RactorizedObject::RactorizedRactor.new(name: "#{args.first}<#{args.first.object_id}>",
&RACTOR_PROC)

      @__ractor_id__ = ractor.object_id

      case mode
      when :object
        ractor << :object

        outside_object = args.first

        @__target_class__ = ::Object.instance_method(:class).bind_call(outside_object)
        puts "tracking #{@__target_class__}<#{::Object.instance_method(:object_id).bind_call(outside_object)}>"

        if ::Ractor.shareable?(outside_object)
          ractor << outside_object
        else
          ::Ractorize.resolve_all_thunks(outside_object)
          ractor.send(outside_object, move: true)
        end
      when :class
        ractor << :class

        klass, *args = args

        ractor << klass

        @__target_class__ = klass

        ::Ractorize.send_args(ractor, klass, args, opts, block)

      else
        # :nocov:
        ::Kernel.raise "Invalid mode #{mode}"
        # :nocov:
      end
      @__object_id__ = ::Object.instance_method(:object_id).bind_call(self)

      # Definitely feels weird and hacky to do this from here but otherwise we get a deadlock
      GarbageCollection.put_ractor(@__object_id__, ractor)
    end

    attr_reader :__object_id__

    def __close__
      method_missing(:__close__).__value__
    end

    def __join__
      object = __close__
      v = object.__value__
      ractor.join
      v
    end

    def method_missing(method_name, *args, **opts, &block)
      ::Kernel.puts "#{@__target_class__}##{method_name} called in ractorized object"
      ractor = self.ractor

      if ractor.nil?
        message = "This ractorized object #{@__object_id__} has no ractor " \
                  "but #{@__target_class__}##{method_name} was called on it!"
        ::Kernel.puts message
        ::Kernel.raise ::Ractor::ClosedError, message
      elsif ractor.default_port.closed? # && method_name != :__close__ && method_name != :__join__
        ::Kernel.raise ::Ractor::ClosedError, "Ractorized object is already closed and cannot be used anymore " \
                                              "but #{@__target_class__}##{method_name} was called on it!"
      end

      return_value_port = ::Ractor::Port.new

      to_move = ::Ractorize.prepare_args(@__target_class__, args, opts)

      if to_move&.any?
        ractor << [:__invoke_arg_by_arg__, [].freeze, {}.freeze, return_value_port, !!block]

        args_port = return_value_port.receive
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
        ractor << [method_name, args.dup.freeze, opts.dup.freeze, return_value_port, !!block].freeze
      end

      if block
        stop = false
        value = nil

        until stop
          data = return_value_port.receive

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

        return_value_port.close

        value
      # Let's assume the user would rather block on all predicate methods than
      # incorrectly get a non-truthy value (thunk is always truthy even if it evaluates as nil/false)
      elsif method_name == :== || method_name == :! || method_name == :!= ||
            method_name == :inspect || method_name == :to_s ||
            method_name.end_with?("?") || method_name == :hash
        value = return_value_port.receive

        return_value_port.close
        # :nocov:
        ::Kernel.raise ::Ractorize::Thunk::EscapingRactorError if ::Ractorize::Thunk === value
        # :nocov:

        value
      else
        ::Ractorize::GarbageCollection.create_thunk(@__object_id__, return_value_port)
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
    def equal?(other) = method_missing(:equal?, other) || super
    def to_s = inspect

    def inspect
      object_id = ::Object.instance_method(:object_id).bind(self).call
      moved_object_inspect = if ractor&.default_port&.closed?
                               ::Object.instance_method(:object_id).bind_call(self)
                             else
                               method_missing(:inspect)
                             end

      "RactorizedObject<#{object_id}>[#{moved_object_inspect}]".freeze
    end

    def ractor
      ::Ractorize::GarbageCollection.get_ractor(@__object_id__)
    end
  end
end
