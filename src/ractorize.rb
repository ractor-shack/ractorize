# TODO: make use of autoload?
require_relative "ractorize/ractorized_object"
require_relative "ractorize/ractorized_class"

module Ractorize
  # Putting this in a constant so we can get test coverage on it since not sure how to get coverage
  # on something inside a ractor.
  RACTOR_PROC = proc do
    object = receive

    loop do
      method_name, method_args, opts, return_port = receive

      case method_name
      when :__close__
        return_port.<<(object, move: true)
        close
        break
      else
        value = object.__send__(method_name, *method_args, **opts)

        return_port << value
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
