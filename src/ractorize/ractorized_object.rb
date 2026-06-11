# TODO: make use of autoload?
require_relative "thunk"

module Ractorize
  class RactorizedObject < BasicObject
    class << self
      def track_thunk(ractorized_object, thunk)
        ractorized_object_id = ractorized_object.__object_id__
        puts "tracking a thunk!!! #{ractorized_object_id}"
        tracked_thunks = Ractor[:tracked_thunks] ||= {}
        thunks = tracked_thunks[ractorized_object_id] ||= []
        thunks << thunk

        tracked_thunks = Ractor[:thunks_to_ractorized_objects] ||= {}
        tracked_thunks[thunk] = ractorized_object_id
      end

      def untrack_thunk(thunk)
        ractorized_object_id = Ractor[:thunks_to_ractorized_objects]&.[](thunk)

        if ractorized_object_id
          Ractor[:tracked_thunks].delete(ractorized_object_id)
        end
      end

      def abandon_thunk(thunk)
        ractorized_object_id = Ractor[:thunks_to_ractorized_objects]&.[](thunk)

        if ractorized_object_id
          thunk = Ractor[:tracked_thunks][ractorized_object_id].delete(thunk)
          thunk.abandon!
        end
      end

      def abandon_thunks(ractorized_object_id)
        puts "abandon thunks called for #{ractorized_object_id}"
        tracked_thunks = Ractor[:tracked_thunks]

        if tracked_thunks
          thunks = tracked_thunks[ractorized_object_id]

          if thunks
            puts "abandoning #{thunks.size} thunks!!"
            thunks.each do |thunk|
              Ractor[:thunks_to_ractorized_objects].delete(thunk)
              thunk.abandon!
            end
            tracked_thunks[ractorized_object_id] = nil
          end
        end
      end

      def setup_finalizer_proc
        proc do |id|
          puts "finalizing a ractorized object with #{id}"

          ractorized_objects = Ractor[:ractorized_objects]

          if ractorized_objects
            ractor = ractorized_objects[id]
            if ractor
              puts "found ractor yaaaaaaaaay!!! #{ractor}"

              if ractor.default_port.closed?
                puts "already closed so doing nothing"
              else
                puts "sending __close__"
                # return_port = ::Ractor::Port.new
                return_port = nil
                ractor << [:__close__, nil, nil, return_port, nil].freeze
                puts "sent __close__"
                begin
                  # object = return_port.receive
                  # puts "got object from __close__"
                  # Ractorize.each_thunk(object, &:abandoned!)
                  # Ractorize.each_ractorized_object(object) do
                  #   it.__close__
                  # rescue ::Ractor::ClosedError
                  #   # do nothing
                  # end
                rescue Ractor::ClosedError
                  # do nothing
                end
                # ractor.join
                # ::Ractorize::RactorizedObject.abandon_thunks(id)
              end
            else
              puts "hmmm no ractor found in finalizer??"
            end
          end
        end
      end

      def setup_finalizer(ractorized_object, ractor)
        ractorized_objects = Ractor[:ractorized_objects] ||= ObjectSpace::WeakMap.new

        ractorized_objects[ractorized_object.__ractorized_object_id__] = ractor
        ObjectSpace.define_finalizer(ractorized_object, &setup_finalizer_proc)
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

      __object_id__
      ::Object.instance_method(:freeze).bind(self).call
    end

    def __ractorized_object_id__
      ::Object.instance_method(:object_id).bind_call(self)
    end

    def __close__
      # if @ractor.default_port.closed?
      #   @ractor.value
      # else
      # hmmm can't undefine this on self since we are frozen.
      # Do we really need to freeze our self? We won't be shareable if we're not frozen ugg.
      # ::ObjectSpace.undefine_finalizer(self)
      v = method_missing(:__close__).__value__

      # TODO: don't blow them all away! Only the ones for this ractorized object!
      ::Ractor[:thunk_id_to_port]&.each_key do |thunk_id|
        ::Kernel.puts "closing a port in __close__"
        port = ::Ractorize::Thunk.remove_port_for(thunk_id)

        unless port
          ::Kernel.puts "strange... didn't find a port??"
        end
        port&.close
      rescue Ractor::ClosedError
        # do nothing
      end
      ::Ractor[:thunk_id_to_port] = nil
      #       end

      v
    end

    def __join__
      ::Kernel.puts "__close__"
      object = __close__
      ::Kernel.puts "__value__"
      v = object.__value__
      ::Kernel.puts "join"
      @ractor.join
      ::Kernel.puts "got value"
      v
    end

    def method_missing(method_name, *args, **opts, &block)
      # return @__final_value__ if defined?(@__final_value__)

      ::Kernel.puts method_name
      if @ractor.default_port.closed? # && method_name != :__close__ && method_name != :__join__
        ::Kernel.raise ::Ractor::ClosedError, "Ractorized object is already closed and cannot be used anymore"
        # return @ractor.value if method_name == :__close__ || method_name == :__join__
        #
        # return @ractor.value.send(method_name, *args, **opts, &block)
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
            method_name == :inspect || method_name == :to_s ||
            method_name.end_with?("?") || method_name == :hash
        value = return_port.receive

        return_port.close
        # :nocov:
        ::Kernel.raise ::Ractorize::Thunk::EscapingRactorError if ::Ractorize::Thunk === value
        # :nocov:

        value
      else
        ::Kernel.puts "thunk created for port #{return_port} in #{::Ractor.current} for #{method_name}"
        Thunk.new(return_port)
        # ::Ractorize::RactorizedObject.track_thunk(self, thunk)

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

    def __object_id__
      return @__object_id__ if defined?(@__object_id__)

      @__object_id__ = ::Object.instance_method(:object_id).bind_call(self)
    end

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
