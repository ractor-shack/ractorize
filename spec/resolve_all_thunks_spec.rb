RSpec.describe Ractorize do
  describe ".resolve_all_thunks" do
    let(:thunk) do
      o = Ractorize[Object.new]
      o.methods
    end

    let(:structure) do
      o = Object.new

      class << o
        attr_accessor :foo
      end

      o.foo = thunk

      [{ o: }]
    end

    it "resolves the thunks" do
      expect(described_class::Thunk === structure[0][:o].foo).to be true
      expect(thunk.__resolved__?).to be_falsey

      described_class.resolve_all_thunks(structure)

      expect(thunk.__resolved__?).to be_truthy
      expect(thunk).to be_a(Array)
      expect(thunk).to include(:object_id)
    end
  end
end
