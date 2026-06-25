RSpec.describe "possible deadlock situation" do
  it "does not deadlock" do
    class RactorizedA
      def foo
        "foo" + GLOBALS.ractorized_b.bar
      end

      def baz = "baz"
    end

    class RactorizedB
      def bar
        # Because there's no need to resolve this thunk, it should not result in a deadlock
        GLOBALS.ractorized_a.baz
        "bar"
      end
    end

    globals = Object.new

    class << globals
      attr_accessor :ractorized_a, :ractorized_b
    end

    globals.ractorized_a = Ractorize[RactorizedA].new
    globals.ractorized_b = Ractorize[RactorizedB].new
    globals.freeze
    GLOBALS = globals

    thunk = GLOBALS.ractorized_a.foo
    expect(Ractorize::Thunk === thunk).to be true
    expect(thunk).to eq("foobar")

    [:GLOBALS, :RactorizedA, :RactorizedB].each do |const|
      Object.__send__(:remove_const, const)
    end
  end
end
