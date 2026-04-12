class Ractorize
  class MethodRunnerRactor < Ractor
    class << self
      def new
        super do
          case receive
          in :ping, return_port
            return_port.send(:pong)
          in :close
            ractor.close
            break
          in target, method_name, args, opts, return_port
            puts "target.object_id #{target.object_id}"
            puts "calling target method #{method_name}"
            return_value = target.send(method_name, *args, **opts)
            return_port.send([target, return_value], move: true)
          end
        end
      end
    end
  end

  module RactorizedObject
    attr_accessor :__method_runner_ractor__

    def initialize(*, method_runner_ractor: MethodRunnerRactor.new, **, &)
      define_singleton_method(:__method_runner_ractor__, &Ractor.shareable_proc(self: method_runner_ractor) { self })
      super(*, **, &)
    end
  end

  class << self
    def ractorize_instances(klass, methods = klass.instance_methods(false))
      klass.prepend(RactorizedObject)
      ractorize_methods(klass, methods)
    end

    def ractorize_methods(klass, methods = klass.instance_methods(false))
      class_name = klass.name

      match = /(\w+)::(\w+)/.match(class_name)

      if match
        parent_name = match[1]
        short_class_name = match[2]
        parent = Object.const_get(parent_name)
      else
        short_class_name = class_name
        parent = Object
      end

      module_name = "Ractorized#{short_class_name}Module"

      if parent.const_defined?(module_name)
        mod = parent.const_get(module_name)
      else
        mod = Module.new
        parent.const_set(module_name, mod)
        klass.prepend(mod)
      end

      puts "ractorizing mod in #{parent}"

      methods.each do |method_name|
        mod.module_eval(<<~HERE, __FILE__, __LINE__ + 1)
          def #{method_name}(*args, **opts)
            puts "calling #{method_name}"
            puts "ractor runner"
            puts __method_runner_ractor__
            puts "current ractor"
            puts Ractor.current

            if __method_runner_ractor__ == Ractor.current
              puts "calling super"
              puts args.inspect
              puts opts.inspect

              begin
                super
              rescue Ractor::MovedError
                puts "moved error!"
                __method_runner_ractor__.send([:ping, return_port])
                return_port.receive
                retry
              end
            else
              return_port = Ractor::Port.new

              puts "sending #{object_id} to ractor"
              __method_runner_ractor__.send([self, :#{method_name}, args, opts, return_port], move: true)

              Ractorize::ProxyPromise.new(return_port)
            end
          end
        HERE
      end
    end
  end
end
