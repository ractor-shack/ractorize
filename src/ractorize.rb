#!/usr/bin/env ruby

# TODO: make use of autoload?
require_relative "ractorized_object/promise"

class Ractorize
  class << self
    def ractorize(object)
      new(object)
    end
  end

  def initialize(o)
    puts "o.object_id"
    puts o.object_id

    @ractor = Ractor.new do
      object = receive

      puts "object.object_id"
      puts object.object_id

      loop do
        method_name, *method_args, return_port = receive

        break if method_name == :close

        value = object.__send__(method_name, *method_args)

        return_port.send(value)
      end
    end

    @ractor.send(o, move: true)
  end

  def method_missing(method_name, *args)
    return_port = Ractor::Port.new

    @ractor << [method_name, *args, return_port]

    RactorizedObject::Promise.new(return_port)
  end
end
