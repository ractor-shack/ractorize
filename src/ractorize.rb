# TODO: make use of autoload?
require_relative "ractorize/proxy_promise"
require_relative "ractorized_class"

class Ractorize
  class << self
    def ractorize_object(object)
      new(object)
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

  attr_accessor :__object__

  def initialize(outside_object)
    @ractor = Ractor.new do
      ractor = Ractor.current
      object = receive

      loop do
        method_name, method_args, opts, return_port = receive

        case method_name
        when :close
          return_port.send(object, move: true)
          ractor.close
          break
        else
          value = object.__send__(method_name, *method_args, **opts)

          return_port.send(value)
        end
      end
    end

    @ractor.send(outside_object, move: true)
  end

  def close
    join
  end

  def join
    returned_object = Ractor::Port.new
    @ractor.send([:close, [], {}, returned_object])
    self.__object__ = returned_object.receive
    @ractor.join
    self
  end

  def method_missing(method_name, *args, **opts)
    if @ractor.default_port.closed?
      __object__.__send__(method_name, *args, **opts)
    else
      return_port = Ractor::Port.new

      @ractor << [method_name, args, opts, return_port]

      Ractorize::ProxyPromise.new(return_port)
    end
  end

  def respond_to_missing?(method_name, include_all = false)
    __object__.respond_to?(method_name, include_all)
  end
end
