# TODO: make use of autoload?
require_relative "ractorize/ractorized_object"
require_relative "ractorize/ractorized_class"

module Ractorize
  class << self
    def ractorize_object(object)
      RactorizedObject.new(:object, object)
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

    # TODO: figure out a way to magically get a ractor-shareable proc from a non-ractor-shareable proc
    def auto_freeze(target, class_or_proc = nil)
      @auto_freeze = @auto_freeze ? @auto_freeze.dup : []

      unless Ractor.shareable?(target)
        # simplecov:disable
        raise "#{target} isn't shareable so can't use it to auto-freeze"
        # simplecov:enable
      end

      @auto_freeze << if class_or_proc
                        unless Ractor.shareable?(class_or_proc)
                          # simplecov:disable
                          raise "#{class_or_proc} isn't shareable so can't use it to auto-freeze"
                          # simplecov:enable
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
        # simplecov:disable
        raise "#{target} isn't shareable so can't use it to auto-freeze"
        # simplecov:enable
      end

      @move_arg << if class_or_proc
                     unless Ractor.shareable?(class_or_proc)
                       # simplecov:disable
                       raise "#{class_or_proc} isn't shareable so can't use it to auto-freeze"
                       # simplecov:enable
                     end

                     [target, class_or_proc]
                   else
                     target
                   end

      @move_arg.freeze
    end

    def any_thunks?(structure)
      # rubocop:disable-next Lint/UnreachableLoop
      each_thunk(structure) { return true }
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

      return nil if skip_move

      to_move(target_class, args)
    end

    def each_thunk(structure, seen = Set.new, &)
      each_instance_of(Thunk, structure, seen, 0, &)
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
          # simplecov:disable
          ::Kernel.raise "Unknown class_by_arg arg type #{arg_type}"
          # simplecov:enable
        end
      end

      [args, opts, block]
    end

    private

    def each_instance_of(klass, structure, seen = Set.new, depth = 0, &block)
      depth += 1
      if klass === structure
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
          value = iget.bind(structure).call(var)
          each_instance_of(klass, value, seen, depth, &block)
        end
      end

      nil
    end
  end
end
