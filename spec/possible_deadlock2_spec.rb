RSpec.describe "possible deadlock situation" do
  before do
    # WARNING: For some reason, stub_class explodes in this situation, hmmmmmmm.....
    class RactorizedA
      def foo = GLOBALS.ractorized_b.bar
      def baz = "baz"
    end

    class RactorizedB
      def bar = "bar" + GLOBALS.ractorized_a.baz
    end

    globals = Object.new

    class << globals
      attr_accessor :ractorized_a, :ractorized_b
    end

    globals.ractorized_a = Ractorize[RactorizedA].new
    globals.ractorized_b = Ractorize[RactorizedB].new
    globals.freeze

    GLOBALS = globals
  end

  after do
    [:GLOBALS, :RactorizedA, :RactorizedB].each do |const|
      Object.__send__(:remove_const, const)
    end
  end

  it "does not deadlock" do
    thunk = GLOBALS.ractorized_a.foo

    expect(Ractorize::Thunk === thunk).to be true
    expect(thunk).to eq("barbaz")
  end
end
