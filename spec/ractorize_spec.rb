RSpec.describe Ractorize do
  describe ".[]" do
    let(:doubler_class) do
      stub_class("Doubler") do
        def set(integer) = @i = integer
        def get = @i
        def double = @i *= 2
      end
    end

    context "when ractorizing an object" do
      let(:doubler) { doubler_class.new }

      let(:ractorized_doubler) { described_class[doubler] }

      it "can be used through its normal interface" do
        ractorized_doubler.set(5)
        expect(ractorized_doubler.get).to eq(5)
        ractorized_doubler.double
        expect(ractorized_doubler.get).to eq(10)
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
      end
    end
  end
end
