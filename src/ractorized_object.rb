#!/usr/bin/env ruby

# TODO: make use of autoload?
require_relative "ractorized_object/promise"

class RactorizedObject < Ractor
  class << self
    def new
      wrap_methods

      super do
        loop do
          method_name, *args, return_port = receive

          break if method_name == :close

          puts "calling #{method_name}_sync"
          puts self
          value = Ractor.current.__send__("#{method_name}_sync", *args)

          return_port.send(value)
        end
      end
    end

    def wrap_methods
      instance_methods(false).each do |method_name|
        alias_method "#{method_name}_sync", method_name
        wrap_method(method_name)
        wrap_method_async(method_name)
      end
    end

    def wrap_method(method_name)
      class_eval <<~HERE, __FILE__, __LINE__ + 1
        def #{method_name}(*args)
          # puts "#{method_name} called!"
          return_port = Ractor::Port.new
          self << [:#{method_name}, args, return_port]
          return_port.receive
        end
      HERE
    end

    def wrap_method_async(method_name)
      class_eval <<~HERE, __FILE__, __LINE__ + 1
        def #{method_name}_async(*args)
          # puts "async call to #{method_name}"
          return_port = Ractor::Port.new
          self << [:#{method_name}, args, return_port]
          Promise.new(return_port)
        end
      HERE
    end
  end
end
