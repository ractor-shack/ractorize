require_relative "ractorize/proxy_promise"

module RactorizedObject
  class << self
    def [](object, methods_to_ractorize = nil)
      if methods_to_ractorize.nil?
        methods_to_ractorize = object.methods
      end

      ractor = Ractor.new do
        target = receive

        loop do
          method_name, method_args, opts, return_port = receive

          case method_name
          when :close
            return_port.send(target, move: true)
            Ractor.current.close
            break
          else
            value = target.__send__(method_name, *method_args, **opts)

            return_port.send(value)
          end
        end
      end

      mod = Module.new

      methods_to_ractorize.each do |method_name|
        mod.define_method(method_name) do |*args, **opts|
          if Ractor.current == ractor
            super
          else
            return_port = Ractor::Port.new
            ractor.send([method_name, args, opts, return_port])
            Ractorize::ProxyPromise.new(return_port)
          end
        end
      end

      object.extend(mod)

      ractor.send(object, move: true)

      object
    end
  end
end
