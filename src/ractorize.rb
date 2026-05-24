# TODO: make use of autoload?
require_relative "ractorize/ractorized_object"
require_relative "ractorize/ractorized_class"

module Ractorize
  class << self
    def any_thunks?(structure, seen = Set.new)
      return true if Thunk === structure
      return false if seen.include?(structure)

      seen << structure

      case structure
      when Array
        structure.any? { any_thunks?(it, seen) }
      when Hash
        any_thunks?(structure.keys, seen) || any_thunks?(structure.values, seen)
      when Struct
        any_thunks?(structure.values)
      else
        ivarsget = ::Object.instance_method(:instance_variables)
        iget = ::Object.instance_method(:instance_variable_get)

        ivarsget.bind(structure).call.any? do |var|
          any_thunks?(iget.bind(structure).call(var), seen)
        end
      end
    end
  end

  # Putting this in a constant so we can get test coverage on it since not sure how to get coverage
  # on something inside a ractor.
  RACTOR_PROC = proc do
    object = receive

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
            return_port << [:yield, [args, opts, b].freeze, block_result_port].freeze

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

          value = value.__value__ while Thunk === value

          return_port << value
        end
      end
    end

    object
  end

  class << self
    def ractorize_object(object)
      RactorizedObject.new(object)
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
