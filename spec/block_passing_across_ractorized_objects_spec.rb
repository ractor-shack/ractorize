RSpec.describe "possible deadlock situation when using blocks" do
  before do
    # WARNING: For some reason, stub_class explodes in this situation, hmmmmmmm.....
    class RactorizedA
      def foo
        yield
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
  end

  after do
    [:GLOBALS, :RactorizedA, :RactorizedB].each do |const|
      Object.__send__(:remove_const, const)
    end
  end

  it "does not deadlock" do
    thunk = GLOBALS.ractorized_a.foo { GLOBALS.ractorized_a.baz }

    # TODO: why isn't it a thunk in this case???
    # expect(Ractorize::Thunk === thunk).to be true
    expect(thunk).to eq("foobar")
  end
end
