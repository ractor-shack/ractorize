#!/usr/bin/env ruby

# TODO: make use of autoload?
require_relative "ractorized_object/promise"

class Ractorized
  def initialize(klass, *args)
    @ractor = Ractor.new(klass, *args) do |klass, *args|
      object = klass.new(*args)

      loop do
        method_name, *method_args, return_port = receive

        break if method_name == :close

        puts method_name.inspect
        puts method_args.inspect

        value = object.__send__(method_name, *method_args)

        return_port.send(value)
      end
    end
  end

  def method_missing(method_name, *args)
    return_port = Ractor::Port.new

    async = method_name.end_with?("_async")

    if async
      method_name = method_name.to_s.gsub(/_async$/, "").to_sym
    end

    @ractor << [method_name, *args, return_port]

    async ? return_port : return_port.receive
  end
end
