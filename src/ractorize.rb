# TODO: make use of autoload?
require_relative "ractorize/ractorized_object"
require_relative "ractorize/ractorized_class"

module Ractorize
  class << self
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
    end

    def each_thunk(structure, seen = Set.new, &block)
      return block.call(structure) if Thunk === structure
      return if seen.include?(structure)

      seen << structure

      case structure
      when Array
        structure.each { each_thunk(it, seen, &block) }
      when Hash
        each_thunk(structure.keys, seen, &block)
        each_thunk(structure.values, seen, &block)
      when Struct
        each_thunk(structure.values, seen, &block)
      else
        ivarsget = ::Object.instance_method(:instance_variables)
        iget = ::Object.instance_method(:instance_variable_get)

        ivarsget.bind(structure).call.each do |var|
          each_thunk(iget.bind(structure).call(var), seen, &block)
        end
      end
    end
  end

  # Putting this in a constant so we can get test coverage on it since not sure how to get coverage
  # on something inside a ractor.
  RACTOR_PROC = proc do
    mode = receive

    object = case mode
             when :class
               klass, args, opts, block = receive
               klass.new(*args.freeze, **opts.freeze, &block)
             when :object
               receive
             when :class_arg_by_arg
               klass = receive

               args = []
               opts = {}
               block = nil

               loop do
                 arg_type = receive

                 case arg_type
                 when :arg
                   args << receive
                 when :kwarg
                   name = receive
                   value = receive

                   opts[name] = value
                 when :block
                   block = receive
                 when :done
                   break
                 else
                   # :nocov:
                   ::Kernel.raise "Unknown class_by_arg arg type #{arg_type}"
                   # :nocov:
                 end
               end

               klass.new(*args.freeze, **opts.freeze, &block)
             else
               # :nocov:
               ::Kernel.raise "Invalid mode #{mode}"
               # :nocov:
             end

    loop do
      method_name, method_args, opts, return_port, block_given = receive

      case method_name
      when :__close__
        return_port.<<(object, move: true)
        close
        break
      else
        if block_given
          block_result_port = Ractor::Port.new

          value = object.__send__(method_name, *method_args, **opts) do |*args, **opts, &b|
            ::Ractorize.resolve_all_thunks(args)
            ::Ractorize.resolve_all_thunks(opts)

            return_port << [:yield, [args.dup.freeze, opts.dup.freeze, b].freeze, block_result_port].freeze

            outcome_type, return_value = block_result_port.receive

            case outcome_type
            when :normal
              return_value
            when :break
              break return_value
            else
              # :nocov:
              ::Kernel.raise "Not sure how to handle outcome_type #{outcome_type}"
              # :nocov:
            end
          end

          return_port << [:return, value].freeze
        else
          value = object.__send__(method_name, *method_args, **opts)

          value = value.__value__ while Thunk === value

          return_port << value
        end
      end
    end

    object
  rescue => e
    # :nocov:
    ::Kernel.puts
    ::Kernel.puts "an error!!! #{e.class} #{e.message} #{e}"
    ::Kernel.puts e.backtrace
    ::Kernel.puts

    raise
    # :nocov:
  end

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
  end
end
