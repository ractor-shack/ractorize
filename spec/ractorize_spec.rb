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
        ractorized_doubler.join
        expect(ractorized_doubler.respond_to?(:set) == true).to be true
        expect(ractorized_doubler.respond_to?(:asdf) == true).to be false
      end

      it "results in proxies that can be used with its normal interface" do
        ractorized_doubler.set(5)
        proxy = ractorized_doubler.get
        expect(proxy).to be_truthy
        expect(!proxy).to be_falsey
        expect(proxy * proxy).to eq(25)
        ractorized_doubler.join
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
        ractorized_doubler.join
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

  describe "#close" do
    context "when calling it twice" do
      it "is idempotent" do
        ractorized_doubler.set(5)
        expect(ractorized_doubler.get).to eq(5)
        ractorized_doubler.double
        expect(ractorized_doubler.get).to eq(10)
        ractorized_doubler.close
        ractorized_doubler.close
        expect(ractorized_doubler.get).to eq(10)
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
      ractor_like_object.send([:close, [], {}, return_port])
      ractor_like_object.join
    end
  end
end
