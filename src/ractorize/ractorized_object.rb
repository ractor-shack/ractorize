# TODO: make use of autoload?
require_relative "thunk"

module Ractorize
  class RactorizedObject < BasicObject
    class << self
      def method_should_use_thunk?(method_symbol)
        method_symbol != :== && method_symbol != :! && method_symbol != :!= &&
          method_symbol != :inspect && method_symbol != :to_s &&
          !method_symbol.end_with?("?") && method_symbol != :hash
      end
    end

    attr_reader :__object_id__, :__ractor__

    def initialize(mode, *args, **opts, &block)
      @__ractor__ = RactorizedRactor.new(name: "#{args.first}<#{args.first.object_id}>".freeze)

      case mode
      when :object
        @__ractor__ << :object

        outside_object = args.first
        @__target_object_id__ = ::Object.instance_method(:object_id).bind_call(outside_object)
        @__target_class__ = outside_object.class

        @__ractor__.send(outside_object, move: true)
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

        return_port = ::Ractor::Port.new
        @__ractor__ << [:__target_object_id__, return_port].freeze
        @__target_object_id__ = return_port.receive
      else
        # simplecov:disable
        ::Kernel.raise "Invalid mode #{mode}"
        # simplecov:enable
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

      return_port = ::Ractorize::RactorizedObject::RactorizedRactor::Port.new

      can_use_thunk = RactorizedObject.method_should_use_thunk?(method_name)

      thunk_ractor = if !block && can_use_thunk
                       ::Ractorize::Thunk::ThunkRactor.new
                     end

      to_move = ::Ractorize.prepare_args(@__target_class__, args, opts)

      if to_move&.any?
        @__ractor__ << [:__invoke_arg_by_arg__, [].freeze, {}.freeze, return_port, thunk_ractor, !!block]

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
        @__ractor__ << [method_name, args.dup.freeze, opts.dup.freeze, return_port, thunk_ractor, !!block].freeze
      end

      if block
        stop = false
        value = nil

        until stop
          data = return_port.receive

          # Seems SimpleCov branch coverage doesn't like that we don't test the non-exhaustive
          # pattern path, but since that's purely defensive I have no interest in testing it.

          # simplecov:disable
          case data
          # simplecov:enable
          in :return, value
            stop = true
          in :yield, [yielded_args, yielded_opts, yielded_block], block_result_port
            # TODO: yielded_block likely won't work when actually used
            # so we should probably instead just raise an exception
            begin
              broke = true
              block_result = block.call(*yielded_args.freeze, **yielded_opts.freeze, &yielded_block)
              broke = false
            ensure
              block_result_port << if broke
                                     # TODO: handle error situation
                                     :break
                                   else
                                     [:normal, block_result].freeze
                                   end
            end
          end
        end

        unless can_use_thunk
          # It's important we don't accidentally return a thunk (truthy) instead of nil/false (falsey)
          value = value.__value__ while ::Ractorize::Thunk === value
        end

        value
      # Let's assume the user would rather block on all predicate methods than
      # incorrectly get a non-truthy value (thunk is always truthy even if it evaluates as nil/false)
      elsif thunk_ractor
        return_port.close
        Thunk.new(thunk_ractor)
      else
        value = return_port.receive
        return_port.close

        # It's important we don't accidentally return a thunk (truthy) instead of nil/false (falsey)
        value = value.__value__ while ::Ractorize::Thunk === value

        value
      end
    end

    def respond_to?(method_name, include_all = false)
      # simplecov:disable
      # This line is only here for when commenting out < BasicObject when debugging stuff
      return super if ::Object === self
      # simplecov:enable

      respond_to_missing?(method_name, include_all)
    end

    def respond_to_missing?(method_name, include_all = false)
      method_missing(:respond_to?, method_name, include_all)
    end

    def ==(other) = method_missing(:==, other) || super
    def !=(other) = method_missing(:==, other) || super
    def ! = method_missing(:!)
    # def equal?(other) = method_missing(:equal?, other) || super
    def to_s = inspect

    # delegating this to the target object increases risk of a deadlock since
    # sometimes #inspect calls #inspect on other objects and can lead to reentry and thus deadlock
    def inspect
      object_id = ::Object.instance_method(:object_id).bind(self).call
      "RactorizedObject<#{object_id}>[#{@__target_class__}<#{@__target_object_id__}>]} #{__state__}"
    end

    def __state__ = @__ractor__.inspect[/ (\w+)>\z/, 1]
  end
end
