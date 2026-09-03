RSpec.describe "predicate method that calls a non-predicate method on another ractorized object" do
  before do
    # WARNING: For some reason, stub_class explodes in this situation, hmmmmmmm.....
    class RactorizedA
      # This is a really bad example... just adding ? to sum to make it follow the code path
      # but is certainly confusing!!
      def global_array_include? = GLOBALS.ractorized_array.is_included(yield)
    end

    globals = Object.new

    class << globals
      attr_accessor :ractorized_a, :ractorized_array
    end

    globals.ractorized_a = Ractorize[RactorizedA].new
    array = [1, 2, 3]

    # rubocop:disable-next Naming/PredicateMethod
    def array.is_included(i) = include?(i)

    array.freeze
    globals.ractorized_array = Ractorize[array]
    globals.freeze

    GLOBALS = globals
  end

  after do
    [:GLOBALS, :RactorizedA].each do |const|
      Object.__send__(:remove_const, const)
    end
  end

  it "does not deadlock" do
    is_included = GLOBALS.ractorized_a.global_array_include? { 4 }

    # It's important we don't accidentally return a thunk (truthy) instead of nil/false (falsey)
    expect(Ractorize::Thunk === is_included).to be false
    expect(is_included).to be_falsey

    is_included = GLOBALS.ractorized_a.global_array_include? { 3 }

    # It's important we don't accidentally return a thunk (truthy) instead of nil/false (falsey)
    expect(Ractorize::Thunk === is_included).to be false
    expect(is_included).to be_truthy
  end
end
