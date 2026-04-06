#!/usr/bin/env ruby

# TODO: make use of autoload?
require_relative "ractorized_object/promise"

class Ractorized
  class << self
    attr_accessor :target_class

    def [](klass)
      ractorized_class = Class.new(Ractorized)
      ractorized_class.target_class = klass
      ractorized_class
    end
  end

  def initialize(*args)
    @ractor = Ractor.new(self.class.target_class, *args) do |klass, *args|
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
