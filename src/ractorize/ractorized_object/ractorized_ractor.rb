require_relative "../base_ractor"

module Ractorize
  class RactorizedObject < BasicObject
    class RactorizedRactor < ::BaseRactor
      class << self
        def new(name: nil)
          super do
            mode = receive

            object = case mode
                     when :class
                       klass, args, opts, block = receive
                       target_class = klass
                       klass.new(*args.freeze, **opts.freeze, &block)
                     when :object
                       o = receive
                       target_class = o.class
                       o
                     when :class_arg_by_arg
                       klass = receive
                       target_class = klass

                       args, opts, block = Ractorize.extract_args(self)

                       klass.new(*args.freeze, **opts.freeze, &block)
                     else
                       # :nocov:
                       raise "Invalid mode #{mode}"
                       # :nocov:
                     end

            loop do
              # rubocop:disable Lint/UselessAssignment
              value = method_name = method_args = opts = return_port = thunk_ractor = block_given = nil
              # rubocop:enable Lint/UselessAssignment
              method_name, method_args, opts, return_port, thunk_ractor, block_given = receive

              case method_name
              when :__close__
                begin
                  thunk_ractor&.send([:success, object].freeze, move: true)
                rescue RactorizedRactor::ClosedError
                  # do nothing
                end

                object = nil
                close
                break
              when :__target_object_id__
                return_port = method_args

                target_object_id = ::Object.instance_method(:object_id).bind_call(object)
                return_port << target_object_id
              else
                if method_name == :__invoke_arg_by_arg__
                  args_port = Ractorize::RactorizedObject::RactorizedRactor::Port.new
                  return_port << args_port

                  method_name = args_port.receive
                  method_args, opts = Ractorize.extract_args(args_port)
                end

                if block_given
                  block_result_port = Ractorize::RactorizedObject::RactorizedRactor::Port.new

                  value = object.__send__(method_name, *method_args, **opts) do |*args, **opts, &b|
                    Ractorize.prepare_args(target_class, args, opts, skip_move: true)

                    return_port << [:yield, [args.dup.freeze, opts.dup.freeze, b].freeze, block_result_port].freeze

                    outcome_type, return_value = block_result_port.receive

                    case outcome_type
                    when :normal
                      return_value
                    when :break
                      # TODO: handle error situation
                      break
                    else
                      # :nocov:
                      raise "Not sure how to handle outcome_type #{outcome_type}"
                      # :nocov:
                    end
                  end

                  return_port << [:return, value].freeze
                else
                  value = object.__send__(method_name, *method_args, **opts)
                  value = value.__value__ while Ractorize::Thunk === value

                  begin
                    if thunk_ractor
                      thunk_ractor.send([:success, value].freeze)
                    else
                      return_port << value
                    end
                  rescue IOError => e
                    # Unclear why this sometimes manifests as this error instead of ClosedError but
                    # need to handle them both.
                    # :nocov:
                    raise unless e.message == "closed stream"
                    # :nocov:
                  rescue Ractor::ClosedError
                    # Whoa... this error inherits from StopIteration and will kill the loop!!!
                    # Nothing really to do here but keep the loop going and handle other
                    # method calls to the ractorized object from other ractors.
                  end
                end
              end

              nil
            end

            nil
          # object
          rescue => e
            # :nocov:
            puts
            puts "an unhandled error!!! #{e.class} #{e.message} #{e}"
            puts e.backtrace
            puts

            raise
            # :nocov:
          end
        end
      end
    end
  end
end
