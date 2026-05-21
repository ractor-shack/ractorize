RSpec.describe Ractorize do
  let(:doubler_class) do
    stub_class("Doubler") do
      class << self
        attr_accessor :some_singleton_method
      end

      def set(integer) = @i = integer
      def get = @i
      def double = @i *= 2
    end
  end

  let(:doubler) { doubler_class.new }

  let(:ractorized_doubler) { described_class[doubler] }

  describe ".[]" do
    context "when ractorizing an object" do
      it "can be used through its normal interface" do
        ractorized_doubler.set(5)
        expect(ractorized_doubler.get).to eq(5)
        ractorized_doubler.double
        expect(ractorized_doubler.get).to eq(10)
        expect(ractorized_doubler.respond_to?(:set) == true).to be true
        expect(ractorized_doubler.respond_to?(:asdf) == true).to be false
        ractorized_doubler.__join__
      end

      it "results in proxies that can be used with its normal interface" do
        ractorized_doubler.set(5)
        proxy = ractorized_doubler.get
        expect(proxy).to be_truthy
        expect(!proxy).to be_falsey
        expect(proxy * proxy).to eq(25)
        ractorized_doubler.__join__
      end

      it "results in a ractorized object that is shareable" do
        expect(Ractor.shareable?(ractorized_doubler)).to be true
      end

      context "when it's a shareable object" do
        it "can still wrap it just fine" do
          ractorized_10 = described_class[10]
          expect(ractorized_10).to be_even
        end
      end
    end

    context "when ractorizing a class" do
      let(:ractorized_doubler_class) { described_class[doubler_class] }
      let(:ractorized_doubler) { ractorized_doubler_class.new }

      it "can be used through its normal interface" do
        ractorized_doubler.set(5)
        expect(ractorized_doubler.get).to eq(5)
        ractorized_doubler.double
        expect(ractorized_doubler.get).to eq(10)
      end

      context "when using singleton methods" do
        it "works with the same interface as the ractorized class" do
          expect(ractorized_doubler_class).to respond_to(:some_singleton_method)
          ractorized_doubler_class.some_singleton_method = 10
          expect(ractorized_doubler_class.some_singleton_method).to eq(10)
        end
      end
    end
  end

  describe "#__close__" do
    context "when calling it twice" do
      it "is idempotent" do
        ractorized_doubler.set(5)
        expect(ractorized_doubler.get).to eq(5)
        ractorized_doubler.double
        expect(ractorized_doubler.get).to eq(10)
        ractorized_doubler.__close__

        # We can run into a deadlock if we don't sleep here, ugg.
        # This can happen if the ractor is closed and we send a message to it after it is closed.
        # The return port we send to the Thunk will never actually get a value.
        sleep 0.5
        expect {
          ractorized_doubler.__close__
        }.to raise_error(Ractor::ClosedError)
      end
    end
  end

  describe "RACTOR_PROC" do
    let(:ractor_like_class) do
      Class.new(Thread) do
        def queue
          @queue ||= Queue.new
        end

        def receive
          queue.pop
        end

        def send(message, move: false)
          queue << message
        end

        def close
        end
      end
    end
    let(:ractor_like_object) do
      ractor_like_class.new do
        Thread.current.instance_exec(&described_class::RACTOR_PROC)
      end
    end

    it "delegates messages to the target object" do
      ractor_like_object.send(doubler)
      return_port = Ractor::Port.new
      ractor_like_object.send([:set, [5], {}, return_port])
      return_port.receive
      ractor_like_object.send([:get, [], {}, return_port])
      expect(return_port.receive).to be(5)
      ractor_like_object.send([:__close__, [], {}, return_port])
      ractor_like_object.join
    end

    context "when target object is also ractorized" do
      it "delegates messages to the target object" do
        ractor_like_object.send(described_class[doubler])
        return_port = Ractor::Port.new
        ractor_like_object.send([:set, [5], {}, return_port])
        return_port.receive
        ractor_like_object.send([:get, [], {}, return_port])
        expect(return_port.receive).to be(5)
        ractor_like_object.send([:__close__, [], {}, return_port])
        ractor_like_object.join
      end
    end
  end

  context "when nested ractorized objects" do
    context "when an outer ractorized object receives a thunk from an inner ractorized object" do
      context "when a predicate on a shareable object" do
        let(:outer_ractorized_object) do
          o = Object.new

          class << o
            attr_accessor :inner

            def even? = inner.even?
            def to_s = inner.to_s
          end

          o.inner = described_class[10]

          o
        end

        it "resolves the predicate thunk internally" do
          value = outer_ractorized_object.even?
          expect(value).to be true
          expect(Ractorize::Thunk === value).to be false
        end
      end

      context "when nested non-shareables" do
        let(:outer_class) do
          inner_class

          stub_class("Outer") do
            attr_accessor :inner

            def initialize
              self.inner = Ractorize[Inner].new
            end

            def foo = inner.foo
            def length = inner.foo.length
          end
        end

        let(:inner_class) do
          stub_class("Inner") do
            def foo = @foo ||= Ractorize["asdf"]
          end
        end

        it "resolves the inner thunk" do
          outer = described_class[outer_class].new
          expect(outer.inner.foo.length).to eq(4)
          expect(Ractorize::Thunk === outer.inner.foo.length).to be true
          expect(outer.inner).to be_a(Inner)
          expect(Ractorize::Thunk === outer.inner).to be true
          expect(Ractorize::Thunk === outer.length).to be true
          expect(outer.length).to eq(4)

          value = outer.foo
          expect(value.length).to eq(4)
          expect(value.class).to eq(String)
          expect(value).to eq("asdf")
          expect(Ractorize::Thunk === value).to be true
          expect(Ractorize::Thunk === value.length).to be true
          expect(Ractorize::Thunk === value.__value__).to be false
        end
      end
    end
  end
end
