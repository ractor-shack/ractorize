# TODO: make use of autoload?
require_relative "ractorize/ractorized_object"
require_relative "ractorize/ractorized_class"

module Ractorize
  class << self
    # TODO: figure out a way to magically get a ractor-shareable proc from a non-ractor-shareable proc
    def auto_freeze(target, class_or_proc = nil)
      @auto_freeze = @auto_freeze ? @auto_freeze.dup : []

      unless Ractor.shareable?(target)
        # :nocov:
        raise "#{target} isn't shareable so can't use it to auto-freeze"
        # :nocov:
      end

      @auto_freeze << if class_or_proc
                        unless Ractor.shareable?(class_or_proc)
                          # :nocov:
                          raise "#{class_or_proc} isn't shareable so can't use it to auto-freeze"
                          # :nocov:
                        end

                        [target, class_or_proc]
                      else
                        target
                      end

      @auto_freeze.freeze
    end

    def move_arg(target, class_or_proc = nil)
      @move_arg = @move_arg ? @move_arg.dup : []

      unless Ractor.shareable?(target)
        # :nocov:
        raise "#{target} isn't shareable so can't use it to auto-freeze"
        # :nocov:
      end

      @move_arg << if class_or_proc
                     unless Ractor.shareable?(class_or_proc)
                       # :nocov:
                       raise "#{class_or_proc} isn't shareable so can't use it to auto-freeze"
                       # :nocov:
                     end

                     [target, class_or_proc]
                   else
                     target
                   end

      @move_arg.freeze
    end

    def any_thunks?(structure)
      # rubocop:disable Lint/UnreachableLoop
      each_thunk(structure) { return true }
      # rubocop:enable Lint/UnreachableLoop
      false
    end

    # Unfortunately, can't read from a port that a different ractor made.
    # Not sure why that is but we need to handle that case.
    def resolve_all_thunks(structure)
      each_thunk(structure, &:__value__)
      nil
    end

    def to_move(target_class, args)
      return unless @move_arg

      move_set = nil

      args.each do |arg|
        next if Ractor.shareable?(arg)

        @move_arg.each do |rule|
          if rule.is_a?(::Array)
            target, rule = rule
            next unless target == target_class
          end

          move_it = if rule.is_a?(::Proc)
                      rule.call(arg)
                    else
                      rule === arg
                    end

          if move_it
            move_set ||= Set.new
            move_set << arg
            break
          end
        end
      end

      move_set
    end

    def apply_auto_freeze(target_class, arg)
      return unless @auto_freeze
      return if Ractor.shareable?(arg)

      # TODO: should we handle instance variables like we do with thunks?
      case arg
      when ::Hash
        arg.each_pair do |key, value|
          apply_auto_freeze(target_class, key)
          apply_auto_freeze(target_class, value)
        end
      when ::Array
        arg.each { apply_auto_freeze(target_class, it) }
      end

      return if Ractor.shareable?(arg)

      @auto_freeze.each do |rule|
        if rule.is_a?(::Array)
          target, rule = rule
          next unless target == target_class
        end

        freeze_it = if rule.is_a?(::Proc)
                      rule.call(arg)
                    else
                      rule === arg
                    end

        if freeze_it
          arg.freeze
          break
        end
      end
    end

    def prepare_args(target_class, args, opts, skip_move: false)
      unless opts.empty?
        args = [*args, *opts.values]
      end

      args.each { apply_auto_freeze(target_class, it) }

      ::Ractorize.resolve_all_thunks(args)

      return nil if skip_move

      to_move(target_class, args)
    end

    def each_thunk(structure, seen = Set.new, &)
      each_instance_of(Thunk, structure, seen, 0, &)
    end

    def each_ractorized_object(structure, seen = Set.new, &)
      each_instance_of(RactorizedObject, structure, seen, 0, &)
    end

    def send_args(port_like,
                  klass,
                  args,
                  opts,
                  block = nil)
      to_move = ::Ractorize.prepare_args(klass, args, opts)

      args.each do |arg|
        port_like << :arg
        port_like.send(arg, move: to_move&.include?(arg))
      end

      opts.each_pair do |name, value|
        port_like << :kwarg
        port_like << name
        port_like.send(value, move: to_move&.include?(value))
      end

      if block
        port_like << :block
        port_like << block
      end

      port_like << :done
    end

    def extract_args(port_like)
      args = []
      opts = {}
      block = nil

      loop do
        arg_type = port_like.__send__(:receive)

        case arg_type
        when :arg
          args << port_like.__send__(:receive)
        when :kwarg
          name = port_like.__send__(:receive)
          value = port_like.__send__(:receive)

          opts[name] = value
        when :block
          block = port_like.__send__(:receive)
        when :done
          break
        else
          # :nocov:
          ::Kernel.raise "Unknown class_by_arg arg type #{arg_type}"
          # :nocov:
        end
      end

      [args, opts, block]
    end

    private

    def each_instance_of(klass, structure, seen = Set.new, depth = 0, &block)
      depth += 1
      if klass === structure
        puts "yielding it!!"
        block.call(structure)
      end
      return if seen.include?(structure)

      seen << structure

      case structure
      when Array
        structure.each { each_instance_of(klass, it, seen, depth, &block) }
      when Hash
        each_instance_of(klass, structure.keys, seen, depth, &block)
        each_instance_of(klass, structure.values, seen, depth, &block)
      when Struct
        each_instance_of(klass, structure.values, seen, depth, &block)
      else
        ivarsget = ::Object.instance_method(:instance_variables)
        iget = ::Object.instance_method(:instance_variable_get)

        ivarsget.bind(structure).call.each do |var|
          puts "checking #{var} for #{klass}"
          value = iget.bind(structure).call(var)
          puts "value is nil? #{NilClass === value}"
          each_instance_of(klass, value, seen, depth, &block)
        end
      end

      nil
    end
  end

  # Putting this in a constant so we can get test coverage on it since not sure how to get coverage
  # on something inside a ractor.
  RACTOR_PROC = Ractor.shareable_proc do
    mode = receive

    object = case mode
             when :object
               o = receive
               target_class = o.class
               o
             when :class
               klass = receive
               target_class = klass

               args, opts, block = Ractorize.extract_args(self)

               klass.new(*args.freeze, **opts.freeze, &block)
             else
               # :nocov:
               raise "Invalid mode #{mode}"
               # :nocov:
             end

    puts "ractorized object ractor created for #{target_class}<#{object.object_id}> in #{self}"

    loop do
      method_name = method_args = opts = return_port = block_given = nil
      method_name, method_args, opts, return_port, block_given = receive
      puts "got #{method_name} in ractor #{self}"

      case method_name
      when :__gc__
        GC.start
      when :__close__
        puts "closing for object #{object} with return port: #{return_port.inspect}"
        return_port&.<<(object, move: true)
        object = nil
        method_name = method_args = opts = return_port = block_given = nil
        close
        # Ractorize.resolve_all_thunks(object)
        puts "done with __close__"
        break
      when :__abandon_ports_and_close__
        raise "wtf??"
        ports = method_args
        ports.each { it.close }
        method_args = ports = nil
        close
        break
      else
        if method_name == :__invoke_arg_by_arg__
          args_port = Ractor::Port.new
          return_port << args_port

          method_name = args_port.receive
          method_args, opts = Ractorize.extract_args(args_port)
          args_port.close
        end

        if block_given
          block_result_port = Ractor::Port.new

          value = object.__send__(method_name, *method_args, **opts) do |*args, **opts, &b|
            Ractorize.prepare_args(target_class, args, opts, skip_move: true)

            return_port << [:yield, [args.dup.freeze, opts.dup.freeze, b].freeze, block_result_port].freeze

            outcome_type, return_value = block_result_port.receive

            case outcome_type
            when :normal
              return_value
            when :break
              break return_value
            else
              # :nocov:
              raise "Not sure how to handle outcome_type #{outcome_type}"
              # :nocov:
            end
          end

          return_port << [:return, value].freeze
        else
          value = object.__send__(method_name, *method_args, **opts)
          method_name = method_args = opts = block_given = nil
          value = value.__value__ while Ractorize::Thunk === value

          begin
            return_port.send(value)
            value = return_port = nil
          rescue IOError => e
            # Unclear why this sometimes manifests as this error instead of ClosedError but
            # need to handle them both.
            # :nocov:
            raise unless e.message == "closed stream"
            # :nocov:
          rescue Ractor::ClosedError
            # Whoa... this error inherits from StopIteration and will kill the loop!!!
            # Nothing really to do here but keep the loop going and handle other
            # method calls to the ractorized object from other ractors.
            ::Kernel.puts "hmmmm in ClosedError does that matter??"
          end
        end
      end

      nil
    rescue => e
      puts "WAIT WTF NOT HANDLED??? #{e}"
      raise e
    end

    # object
    nil
  rescue => e
    # :nocov:
    puts
    puts "an unhandled error!!! #{e.class} #{e.message} #{e}"
    puts e.backtrace
    puts

    raise
    # :nocov:
  end

  class << self
    def ractorize_object(object)
      GarbageCollection.create_ractorized_object(:object, object)
    end

    def ractorize_class(klass)
      RactorizedClass[klass]
    end

    def [](object)
      if object.is_a?(Class)
        ractorize_class(object)
      else
        ractorize_object(object)
      end
    end
  end
end
