# TODO: make use of autoload?
require_relative "ractorize/proxy_promise"
require_relative "ractorized_class"

class Ractorize < BasicObject
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
    @ractor = ::Ractor.new do
      object = receive

      loop do
        method_name, method_args, opts, return_port = receive

        case method_name
        when :close
          return_port.<<(object, move: true)
          close
          break
        else
          value = object.__send__(method_name, *method_args, **opts)

          return_port << value
        end
      end
    end

    # It doesn't seem like we have a way to move the object into the ractor via its constructor so do
    # it with #<< instead.
    @ractor.<<(outside_object, move: true)
  end

  def close
    result = method_missing(:close)

    @__object__ = if ProxyPromise === result
                    result.__value__
                  else
                    result
                  end
  end

  def join
    close
    @ractor.join
    self
  end

  def method_missing(method_name, *args, **opts)
    return @__object__ if method_name == :close && @ractor.default_port.closed?

    if defined?(@__object__)
      @__object__.__send__(method_name, *args, **opts)
    else
      return_port = ::Ractor::Port.new

      @ractor << [method_name, args, opts, return_port]

      ProxyPromise.new(return_port)
    end
  end

  def respond_to?(method_name, include_all = false)
    value = method_missing(:respond_to?, method_name, include_all)

    if ::Ractorize::ProxyPromise === value
      value.__value__
    else
      value
    end
  end
end
