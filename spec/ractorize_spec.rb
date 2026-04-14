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
        expect(ractorized_doubler.respond_to?(:asdf) == true).to eq false
        ractorized_doubler.join
        expect(ractorized_doubler.respond_to?(:set) == true).to be true
        expect(ractorized_doubler.respond_to?(:asdf) == true).to eq false
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
end
