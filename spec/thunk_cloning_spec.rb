RSpec.describe "thunk cloning" do
  before do
    class RactorizedA
      def foo = GLOBALS.ractorized_b.bar
    end

    class RactorizedB
      def bar = "bar"
    end

    globals = Object.new

    class << globals
      attr_accessor :ractorized_a, :ractorized_b
    end

    globals.ractorized_a = Ractorize[RactorizedA].new
    globals.ractorized_b = Ractorize[RactorizedB].new
    globals.freeze
    Object.const_set(:GLOBALS, globals)
  end

  after do
    [:GLOBALS, :RactorizedA, :RactorizedB].each do |const|
      Object.__send__(:remove_const, const)
    end
  end

  it "still gives the right answer" do
    thunk = GLOBALS.ractorized_a.foo
    expect(Ractorize::Thunk === thunk).to be true
    expect(Ractor.shareable?(thunk)).to be false

    r = BaseRactor.new { receive }

    r << thunk

    expect(Ractorize::Thunk === r.value).to be true
    expect(Ractor.shareable?(r.value)).to be false
    expect(thunk.__resolved__?).to be_falsey
    expect(r.value.__resolved__?).to be_falsey

    expect(thunk).to eq("bar")
    expect(r.value).to eq("bar")

    expect(thunk.__resolved__?).to be_truthy
    expect(r.value.__resolved__?).to be_truthy

    unless Shmactor.activated?
      expect(r.value.__id__).to_not eq(thunk.__id__)
    end
  end

  context "when manually cloning a thunk before and after it's resolved" do
    it "gives the right answer" do
      thunk = GLOBALS.ractorized_a.foo
      cloned_thunk = Object.instance_method(:clone).bind_call(thunk)

      expect(Ractorize::Thunk === thunk).to be true
      expect(Ractor.shareable?(thunk)).to be false
      expect(Ractorize::Thunk === cloned_thunk).to be true
      expect(Ractor.shareable?(cloned_thunk)).to be false

      expect(thunk.__resolved__?).to be_falsey
      expect(cloned_thunk.__resolved__?).to be_falsey

      expect(thunk).to eq("bar")
      expect(cloned_thunk).to eq("bar")

      expect(thunk.__resolved__?).to be_truthy
      expect(cloned_thunk.__resolved__?).to be_truthy

      expect(cloned_thunk.__id__).to_not eq(thunk.__id__)

      cloned_thunk2 = Object.instance_method(:clone).bind_call(thunk)

      expect(cloned_thunk2.__resolved__?).to be_truthy
      expect(cloned_thunk2).to eq("bar")
    end
  end

  context "when manually cloning a thunk multiple times" do
    it "gives the right answer" do
      thunk = GLOBALS.ractorized_a.foo
      cloned_thunk1 = Object.instance_method(:clone).bind_call(thunk)
      cloned_thunk2 = Object.instance_method(:clone).bind_call(thunk)
      cloned_thunk3 = Object.instance_method(:clone).bind_call(thunk)
      cloned_thunk4 = Object.instance_method(:clone).bind_call(thunk)

      [
        thunk,
        cloned_thunk1,
        cloned_thunk2,
        cloned_thunk3,
        cloned_thunk4
      ].each do |thunk|
        expect(Ractorize::Thunk === thunk).to be true
        expect(Ractor.shareable?(thunk)).to be false
        expect(thunk.__resolved__?).to be_falsey
      end

      # expect(cloned_thunk3).to eq("bar")
      # expect(cloned_thunk3.__resolved__?).to be_truthy

      # rubocop:disable Lint/UselessAssignment
      ractors = [
        thunk,
        cloned_thunk1,
        cloned_thunk2,
        cloned_thunk3,
        cloned_thunk4
      ].map(&:__thunk_ractor__)

      thunk,
cloned_thunk1,
cloned_thunk2,
cloned_thunk3,
cloned_thunk4 = nil

      GC.start
      GC.start
      GC.start
      1_000_000.times { Object.new }
      GC.start

      ractors = nil
      # rubocop:enable Lint/UselessAssignment

      GC.start
    end
  end
end
