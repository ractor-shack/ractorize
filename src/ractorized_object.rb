#!/usr/bin/env ruby

# TODO: make use of autoload?
require_relative "ractorized_object/promise"

class RactorizedObject < Ractor
  class << self
    def new
      unless const_defined?(:Wrapper)
        wrap_methods
      end

      super do
        ractor = Ractor.current

        loop do
          method_name, *args, return_port = receive

          break if method_name == :close

          old_inside_wrapper = Ractor[:inside_ractor]

          begin
            Ractor[:inside_wrapper] = true

            value = ractor.__send__(method_name, *args)

            return_port.send(value)
          ensure
            Ractor[:inside_wrapper] = old_inside_wrapper
          end
        end
      end
    end

    def wrap_methods
      install_wrapper

      instance_methods(false).each do |method_name|
        wrap_method(method_name)
        wrap_method_async(method_name)
      end
    end

    def wrap_method(method_name)
      # self::Wrapper.define_method :method_name do |*args|
      #   return super if Ractor[:inside_wrapper]
      #
      #   return_port = Ractor::Port.new
      #   self << [method_name, args, return_port]
      #   return_port.receive
      # end

      s = <<~HERE
        def #{method_name}(*args)
          return super if Ractor[:inside_wrapper]

          return_port = Ractor::Port.new
          self << [:#{method_name}, args, return_port]
          return_port.receive
        end
      HERE

      self::Wrapper.class_eval s
    end

    def wrap_method_async(method_name)
      s = <<~HERE
        def #{method_name}_async(*args)
          return_port = Ractor::Port.new
          self << [:#{method_name}, args, return_port]
          Promise.new(return_port)
        end
      HERE

      self::Wrapper.class_eval s
    end

    def install_wrapper
      const_set(:Wrapper, Module.new)
      prepend self::Wrapper
    end
  end
end
