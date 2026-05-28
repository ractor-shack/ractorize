RSpec.describe Ractorize do
  describe ".auto_freeze" do
    around do |example|
      old_to_move = described_class.instance_variable_get(:@auto_freeze).dup

      example.run
    ensure
      described_class.instance_variable_set(:@auto_freeze, old_to_move)
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

    context "when auto-freezing all strings" do
      before do
        Ractorize.auto_freeze(String)
      end

      it "automatically freezes strings that are passed to a ractorized object to prevent duplication" do
        s = "asdf"

        expect {
          expect(ractorized_foo.foo(s)).to eq(s)
        }.to change(s, :frozen?).from(false).to(true)
      end

      context "when the thing to freeze is super deep in the structure" do
        it "still freezes it" do
          s = "asdf"
          structure = {
            foo: [1, 2, s]
          }

          expect {
            expect(ractorized_foo.foo(structure)).to eq(structure)
          }.to change(s, :frozen?).from(false).to(true)
        end

        context "when freezing something makes something shareable" do
          it "works just fine without needing to consider the rest of the structure" do
            s = "asdf"
            structure = {
              foo: [1, 2, s].freeze
            }.freeze

            expect {
              expect(ractorized_foo.foo(structure)).to eq(structure)
            }.to change { Ractor.shareable?(structure) }.from(false).to(true)
          end
        end
      end
    end

    context "when auto-freezing a class for different ractorized object classes" do
      before do
        Ractorize.auto_freeze(foo_klass, String)
      end

      it "freezes objects only when the target class matches the rule" do
        s = "asdf"

        expect {
          expect(ractorized_bar.bar(s)).to eq(s)
        }.to_not change(s, :frozen?)

        expect {
          expect(ractorized_foo.foo(s)).to eq(s)
        }.to change(s, :frozen?).from(false).to(true)
      end
    end

    context "when it's already frozen" do
      it "works just fine" do
        s = "asdf"
        expect(ractorized_foo.foo(s)).to eq(s)
      end
    end

    context "when using procs to determine if something should be frozen" do
      before do
        Ractorize.auto_freeze(Ractor.shareable_proc { it =~ /quux/ })
        Ractorize.auto_freeze(Ractor.shareable_proc { it =~ /baz/ })
      end

      it "only freezes when it matches the rule proc" do
        s = "foo"

        expect {
          expect(ractorized_foo.foo(s)).to eq(s)
        }.to_not change(s, :frozen?)

        s = "bar"

        expect {
          expect(ractorized_foo.foo(s)).to eq(s)
        }.to_not change(s, :frozen?)

        s = "baz"

        expect {
          expect(ractorized_foo.foo(s)).to eq(s)
        }.to change(s, :frozen?).from(false).to(true)
      end
    end
  end
end
