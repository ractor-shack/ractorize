RSpec.describe "predicate method that calls a non-predicate method on another ractorized object" do
  before do
    # WARNING: For some reason, stub_class explodes in this situation, hmmmmmmm.....
    class RactorizedA
      # need to call method without ? in name to get a thunk...
      def sad? = GLOBALS.ractorized_b.is_sad
    end

    class RactorizedB
      # rubocop:disable-next Naming/PredicateMethod
      def is_sad = false
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
    is_sad = GLOBALS.ractorized_a.sad?

    expect(Ractorize::Thunk === is_sad).to be false
    expect(is_sad).to be false
  end
end
