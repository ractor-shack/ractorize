# TODO: move to another gem
# :nocov:
class Counter
  def initialize
    @ractor = Ractor.new do
      count = 0

      loop do
        return_port = receive

        count += 1
        return_port << count
      end
    end

    freeze
  end

  def inc
    p = Ractor::Port.new

    @ractor << p
    p.receive
  end
end

class GlobalVariable
  def initialize
    @ractor = Ractor.new do
      value = nil

      loop do
        method_info = receive

        case method_info
        in :set, return_port, value
          # nothing to do...
        in :get, return_port
          # nothing to do...
        else
          raise "invalid method info #{method_info}"
        end

        return_port << value
      end
    end

    freeze
  end

  def get
    p = Ractor::Port.new

    @ractor << [:get, p].freeze

    p.receive
  end

  def set(value)
    p = Ractor::Port.new

    @ractor << [:set, p, value].freeze

    p.receive
  end
end

ThunkId = GlobalVariable.new
CounterInstance = Counter.new

module LeakyThunkDetection
  def send(object, ...)
    raise_if_leaked_thunk(object)
    super
  end

  def <<(object, ...)
    raise_if_leaked_thunk(object)
    super
  end

  def raise_if_leaked_thunk(thunk)
    if Ractorize::Thunk === thunk
      unless thunk.resolved? || thunk.chained?
        raise "leaking a thunk from here"
      end
    end
  end
end

Ractor.prepend(LeakyThunkDetection)
Ractor::Port.prepend(LeakyThunkDetection)

# :nocov:

module Ractorize
  class Thunk < BasicObject
    class EscapingRactorError < ::StandardError; end

    attr_accessor :__return_value_port__, :__ractor__

    def initialize(return_value_port)
      self.__ractor__ = ::Ractor.current
      self.__return_value_port__ = return_value_port
    end

    def initialize_clone(...)
      # is this actually necessary?? Seems so?
    end

    # This is a pretty confusing method. The snag is only the ractor that created a port can call
    # Ractor::Port#receive on it. So when a Thunk escapes from one ractor to another, we can't
    # really resolve it. So we will instead resolve it here in the current ractor in a Thread
    # and send the result to the port of all other thunks created as it passes from ractor-to-ractor.
    # TODO: can we make this method return a thunk?? Or maybe take/return a thunk? Would be cleaner
    # interface-wise I think.
    def chain(port)
      ::Kernel.puts "chaining!! resolved is: #{resolved?} and chained is: #{chained?}"
      return __value__ if resolved?

      m = __mutex__
      m&.lock

      begin
        if @value_ractor
          ::Thread.new { port << @value_ractor.join.value }
        else
          @value_ractor = ::Ractor.new do
            # make sure we block until the @value_ractor instance variable has had a chance to be set
            # and for good measure until we are locked down and therefore "shareable".
            # Sending the port via #<< from outside accomplishes this.
            p = receive
            value = receive
            p << value
            value
          end

          thread_port = __return_value_port__
          lockdown
          @value_ractor << port
          ::Thread.new { @value_ractor << thread_port.receive }
        end
      ensure
        m&.unlock
      end

      ::Kernel.puts "returning self"
      self
    end

    def method_missing(...)
      __value__.__send__(...)
    end

    def respond_to_missing?(method_name, include_all = false)
      __value__.respond_to?(method_name, include_all)
    end

    def __value__
      if ::ThunkId.get == ::Object.instance_method(:object_id).bind_call(self)
        ::Kernel.puts "__value__ called on target thunk!!"
      end

      m = __mutex__
      m&.lock

      return @__value__ if defined?(@__value__)
      return @value_ractor.join.value if @value_ractor

      if ::Ractor.current == __ractor__
        @__value__ = __return_value_port__.receive

        # :nocov:
        # ::Kernel.raise EscapingRactorError if ::Ractorize::Thunk === value
        # :nocov:

        lockdown

        @__value__
      else
        # :nocov:
        ::Kernel.raise EscapingRactorError,
                       "Somehow this thunk was passed between ractors but wasn't resolved first."
        # :nocov:
      end
    ensure
      m&.unlock
    end

    def resolved?
      defined?(@__value__) || @value_ractor&.default_port&.closed?
    end

    def chained?
      !!@value_ractor
    end

    def ! = !__value__
    def ==(other) = __value__ == other || super
    def !=(other) = __value__ != other || super
    def equal?(other) = __value__.equal?(other) || super

    private

    # After calling this method, one way or another the Thunk should be shareable.
    # Either because it's frozen with just a @__value__ or because it's frozen with just a
    # @value_ractor.
    def lockdown
      m = __mutex__
      m = nil if m&.owned?
      m&.lock

      if defined?(@__value__)
        @value_ractor &&= nil
      elsif @value_ractor&.default_port&.closed?
        @__value__ = @value_ractor.value
        @value_ractor = nil
      end

      self.__return_value_port__ &&= nil
      self.__ractor__ &&= nil
      @__mutex__ &&= nil

      ::Object.instance_method(:freeze).bind(self).call
    ensure
      m&.unlock if m&.owned?
    end

    def __mutex__
      return @__mutex__ if defined?(@__mutex__)

      @__mutex__ = ::Mutex.new
    end
  end
end
