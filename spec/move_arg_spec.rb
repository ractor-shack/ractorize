RSpec.describe Ractorize do
  describe ".move_arg" do
    around do |example|
      old_to_move = described_class.instance_variable_get(:@move_arg).dup

      example.run
    ensure
      described_class.instance_variable_set(:@move_arg, old_to_move)
    end

    let(:foo_klass) do
      stub_class("Foo") do
        def foo(bar) = bar
      end
    end
    let(:ractorized_foo) { Ractorize[foo_klass.new] }
    let(:bar_klass) do
      stub_class("Bar") do
        def bar(baz) = baz
      end
    end
    let(:ractorized_bar) { Ractorize[bar_klass.new] }

    context "when moving all strings" do
      before do
        Ractorize.move_arg(String)
      end

      it "automatically moves strings that are passed to a ractorized object to prevent duplication" do
        s = "asdf"

        expect {
          expect(ractorized_foo.foo(s)).to eq("asdf")
        }.to change { Ractor::MovedObject === s }.from(false).to(true)
      end
    end

    context "when using procs to determine if something should be moved" do
      before do
        Ractorize.move_arg(Ractor.shareable_proc { it =~ /baz/ })
      end

      it "only moves when it matches the rule proc" do
        s = "foo"

        expect {
          expect(ractorized_foo.foo(s)).to eq("foo")
        }.to_not change { Ractor::MovedObject === s }

        s = "bar"

        expect {
          expect(ractorized_foo.foo(s)).to eq("bar")
        }.to_not change { Ractor::MovedObject === s }

        s = "baz"

        expect {
          expect(ractorized_foo.foo(s)).to eq("baz")
        }.to change { Ractor::MovedObject === s }.from(false).to(true)
      end
    end

    context "when auto-freezing a class for different ractorized object classes" do
      before do
        Ractorize.move_arg(foo_klass, String)
      end

      it "freezes objects only when the target class matches the rule" do
        s = "asdf"

        expect {
          expect(ractorized_bar.bar(s)).to eq(s)
        }.to_not change { Ractor::MovedObject === s }

        expect {
          expect(ractorized_foo.foo(s)).to eq("asdf")
        }.to change { Ractor::MovedObject === s }.from(false).to(true)
      end
    end
  end
end
