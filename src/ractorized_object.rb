#!/usr/bin/env ruby

class RactorizedObject < Ractor
  class << self
    def new
      super do
        unless Ractor[:wrapper]
          Ractor.current.class.wrap_methods
        end

        loop do
          method_name, *args, return_port = receive

          break if method_name == :close

          old_inside_wrapper = Ractor[:inside_ractor]

          begin
            Ractor[:inside_wrapper] = true

            value = Ractor.current.__send__(method_name, *args)

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
      end
    end

    def wrap_method(method_name)
      # define_method(method_name) do |*args|
      #   return_port = Ractor::Port.new
      #   send(method_name, *args, return_port)
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

      Ractor[:wrapper].class_eval s
    end

    def install_wrapper
      Ractor[:wrapper] = Module.new
      prepend Ractor[:wrapper]
    end
  end
end
