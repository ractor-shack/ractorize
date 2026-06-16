RSpec.describe Ractorize do
  def self.move_string_args
    before do
      old_to_move = described_class.instance_variable_get(:@to_move).dup

      begin
        described_class.move_arg(String)
      ensure
        described_class.instance_variable_set(:@to_move, old_to_move)
      end
    end
  end

  let(:doubler_class) do
    stub_class("Doubler") do
      class << self
        attr_accessor :some_singleton_method
      end

      def set(integer) = @i = integer
      def get = @i
      def double = @i *= 2
    end
  end

  let(:doubler) { doubler_class.new }

  let(:ractorized_doubler) { described_class[doubler] }

  describe ".[]" do
    context "when ractorizing an object" do
      it "can be used through its normal interface" do
        ractorized_doubler.set(5)

        expect(ractorized_doubler.get).to eq(5)
        ractorized_doubler.double
        expect(ractorized_doubler.get).to eq(10)
        expect(ractorized_doubler.respond_to?(:set) == true).to be true
        expect(ractorized_doubler.respond_to?(:asdf) == true).to be false

        ractorized_doubler.__join__
      end

      it "results in proxies that can be used with its normal interface" do
        ractorized_doubler.set(5)
        proxy = ractorized_doubler.get
        expect(proxy).to be_truthy
        expect(!proxy).to be_falsey
        expect(proxy * proxy).to eq(25)
        ractorized_doubler.__join__
      end

      it "results in a ractorized object that is shareable" do
        expect(Ractor.shareable?(ractorized_doubler)).to be true
      end

      context "when it's a shareable object" do
        it "can still wrap it just fine" do
          ractorized_10 = described_class[10]
          expect(ractorized_10).to be_even
        end
      end

      context "when passing non-shareable keyword args" do
        move_string_args

        let(:klass) do
          stub_class("Foo") do
            def foo(bar:) = bar
          end
        end
        let(:ractorized_object) { described_class[klass.new] }

        it "moves the args to the ractorized object" do
          bar = "bar"

          expect(ractorized_object.foo(bar:)).to eq("bar")
          expect(Ractor::MovedObject === bar).to be true
        end
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
      end

      context "when using singleton methods" do
        it "works with the same interface as the ractorized class" do
          expect(ractorized_doubler_class).to respond_to(:some_singleton_method)
          ractorized_doubler_class.some_singleton_method = 10
          expect(ractorized_doubler_class.some_singleton_method).to eq(10)
        end
      end

      context "when creating an instance with to-move args" do
        move_string_args

        let(:args) { ["foo"] }
        let(:klass) do
          stub_class("Foo") do
            attr_accessor :foo

            def initialize(foo) = self.foo = foo
          end
        end
        let(:ractorized_klass) { described_class[klass] }

        it "moves the args to the new ractor" do
          expect(Ractor.shareable?(args.first)).to be false
          object = ractorized_klass.new(*args)
          expect(object.foo).to eq("foo")
          expect(Ractor::MovedObject === args.first).to be true
        end

        context "when keyword args are not shareable" do
          let(:opts) do
            { foo: "foo" }
          end

          let(:klass) do
            stub_class("Foo") do
              attr_accessor :foo

              def initialize(foo:, &block) = self.foo = foo + block.call
            end
          end

          it "moves the args to the new ractor" do
            expect(Ractor.shareable?(opts[:foo])).to be false
            object = ractorized_klass.new(**opts, &Ractor.shareable_proc { "bar" })
            expect(object.foo).to eq("foobar")
            expect(Ractor::MovedObject === opts[:foo]).to be true
          end
        end
      end
    end
  end

  describe "#__close__" do
    context "when calling it twice" do
      it "raises a ClosedError" do
        ractorized_doubler.set(5)
        expect(ractorized_doubler.get).to eq(5)
        ractorized_doubler.double
        expect(ractorized_doubler.get).to eq(10)
        ractorized_doubler.__close__

        # We can run into a deadlock if we don't sleep here, ugg.
        # This can happen if the ractor is closed and we send a message to it after it is closed.
        # The return port we send to the Thunk will never actually get a value.
        sleep 0.5
        expect {
          ractorized_doubler.__close__
        }.to raise_error(Ractor::ClosedError)
      end
    end
  end

  describe "RACTOR_PROC" do
    let(:ractor_like_class) do
      Class.new(Thread) do
        def queue
          @queue ||= Queue.new
        end

        def receive
          queue.pop
        end

        def send(message, move: false)
          queue << message
        end

        def close
        end
      end
    end
    let(:ractor_like_object) do
      ractor_like_class.new do
        Thread.current.instance_exec(&described_class::RACTOR_PROC)
      end
    end

    it "delegates messages to the target object" do
      ractor_like_object.send(:object)
      ractor_like_object.send(doubler)
      return_port = Ractor::Port.new
      ractor_like_object.send([:set, [5], {}, return_port])
      return_port.receive
      ractor_like_object.send([:get, [], {}, return_port])
      expect(return_port.receive).to be(5)
      ractor_like_object.send([:__close__, [], {}, return_port])
      ractor_like_object.join
    end

    context "when invoking arg-by-arg" do
      it "can still invoke the method" do
        ractor_like_object.send(:object)
        ractor_like_object.send(doubler)
        return_port = Ractor::Port.new

        ractor_like_object.send([:__invoke_arg_by_arg__, [], {}, return_port])
        arg_port = return_port.receive
        arg_port << :set
        arg_port << :arg
        arg_port << 5
        arg_port << :done

        return_port.receive

        ractor_like_object.send([:__invoke_arg_by_arg__, [], {}, return_port])
        arg_port = return_port.receive
        arg_port << :get
        arg_port << :done

        expect(return_port.receive).to be(5)
        ractor_like_object.send([:__close__, [], {}, return_port])
        ractor_like_object.join
      end
    end

    context "when target object is also ractorized" do
      it "delegates messages to the target object" do
        ractor_like_object.send(:object)
        ractor_like_object.send(doubler)
        return_port = Ractor::Port.new
        ractor_like_object.send([:set, [5], {}, return_port])
        return_port.receive
        ractor_like_object.send([:get, [], {}, return_port])
        expect(return_port.receive).to be(5)
        ractor_like_object.send([:__close__, [], {}, return_port])
        ractor_like_object.join
      end
    end

    context "when implementing a method that takes a block" do
      def handle_return_port(return_port, block)
        value = nil

        # pretty terrible to repeat a bunch of this logic here, ugg
        loop do
          # Seems SimpleCov branch coverage doesn't like that we don't test the non-exhaustive
          # pattern path, but since that's purely defensive I have no interest in testing it.
          # :nocov:
          case return_port.receive
            # :nocov:
          in :return, value
            break
          in :yield, [yielded_args, yielded_opts, yielded_block], block_result_port
            # TODO: yielded_block likely won't work when actually used
            # so we should probably instead just raise an exception
            # TODO: handle break and also raise in the block
            block_result_port << begin
              block_result = block.call(*yielded_args, **yielded_opts, &yielded_block)

              [:normal, block_result]
            rescue LocalJumpError => e
              case e.reason
              when :break
                [:break, e.exit_value]
              else
                # :nocov:
                raise "Not sure how to handle LocalJumpError #{e.reason}"
                # :nocov:
              end
            end
          end
        end

        value
      end

      it "can carry executing the block" do
        h = { "foo" => "bar", "baz" => "quux" }

        ractor_like_object.send(:object)
        ractor_like_object.send(h)

        all = []

        return_port = Ractor::Port.new

        block = proc do |key, value|
          all << [key, value]
        end

        ractor_like_object.send([:each_pair, [], {}, return_port, block])

        value = handle_return_port(return_port, block)

        expect(all).to eq([["foo", "bar"], ["baz", "quux"]])
        expect(value).to eq(h)
      end

      context "when block contains 'break'" do
        it "can carry out executing the block" do
          ractor_like_object.send(:class)
          ractor_like_object.send([Hash])

          return_port = Ractor::Port.new

          ractor_like_object.send([:[]=, ["foo", "bar"], {}, return_port])
          ractor_like_object.send([:[]=, ["baz", "quux"], {}, return_port])

          all = []

          return_port = Ractor::Port.new

          block = proc do |key, value|
            all << [key, value]
            break 100
          end

          ractor_like_object.send([:each_pair, [], {}, return_port, block])

          value = handle_return_port(return_port, block)

          expect(all).to eq([["foo", "bar"]])
          expect(value).to eq(100)
        end
      end
    end

    context "when constructing an instance arg-by-arg" do
      let(:klass) do
        stub_class("Foo") do
          attr_accessor :foo

          def initialize(foo, bar:, &block)
            self.foo = foo + bar + block.call
          end
        end
      end

      it "can handle building the object constructor args piece-by-piece" do
        ractor_like_object.send(:class_arg_by_arg)
        ractor_like_object.send(klass)
        ractor_like_object.send(:arg)
        ractor_like_object.send("foo")
        ractor_like_object.send(:kwarg)
        ractor_like_object.send(:bar)
        ractor_like_object.send("bar")
        ractor_like_object.send(:block)
        ractor_like_object.send(Ractor.shareable_proc { "baz" })
        ractor_like_object.send(:done)

        return_port = Ractor::Port.new

        ractor_like_object.send([:foo, [], {}, return_port])

        expect(return_port.receive).to eq("foobarbaz")
      end
    end
  end

  context "when nested ractorized objects" do
    context "when an outer ractorized object receives a thunk from an inner ractorized object" do
      context "when a predicate on a shareable object" do
        let(:outer_ractorized_object) do
          o = Object.new

          class << o
            attr_accessor :inner

            def even? = inner.even?
            def to_s = inner.to_s
          end

          o.inner = described_class[10]

          o
        end

        it "resolves the predicate thunk internally" do
          value = outer_ractorized_object.even?
          expect(Ractorize::Thunk === value).to be false
          expect(value).to be true
        end
      end

      context "when nested non-shareables" do
        let(:outer_class) do
          inner_class

          stub_class("Outer") do
            attr_accessor :inner

            def initialize = self.inner = Ractorize[Inner].new
            def foo = inner.foo
            def length = inner.foo.length
          end
        end

        let(:inner_class) do
          stub_class("Inner") do
            def foo = @foo ||= Ractorize["asdf"]
          end
        end

        it "resolves the inner thunk" do
          outer = described_class[outer_class].new
          expect(outer.inner.foo.length).to eq(4)
          expect(Ractorize::Thunk === outer.inner.foo.length).to be true
          expect(outer.inner).to be_a(Inner)
          expect(Ractorize::Thunk === outer.inner).to be true
          expect(Ractorize::Thunk === outer.length).to be true
          expect(outer.length).to eq(4)

          value = outer.foo
          expect(value.length).to eq(4)
          expect(value.class).to eq(String)
          expect(value).to eq("asdf")
          expect(Ractorize::Thunk === value).to be true
          expect(Ractorize::Thunk === value.length).to be true
          expect(Ractorize::Thunk === value.__value__).to be false
        end
      end
    end
  end

  context "when passing a block across ractors" do
    let(:object) do
      { "foo" => "bar", "baz" => "quux" }
    end
    let(:ractorized_object) { described_class[object] }

    it "can handle blocks" do
      all = []

      ractorized_object.each_pair do |key, value|
        all << [key, value]
      end

      expect(all).to eq([["foo", "bar"], ["baz", "quux"]])
    end

    context "when the block returns a thunk" do
      it "can handle blocks" do
        pair_builder = Object.new
        pair_builder.singleton_class.class_eval do
          def make_pair(a, b) = [a, b]
        end

        pair_builder = described_class[pair_builder]

        all = []

        ractorized_object.each_pair do |key, value|
          pair = pair_builder.make_pair(key, value)
          all << pair
          pair
        end

        expect(all).to eq([["foo", "bar"], ["baz", "quux"]])
      end
    end

    context "when the block contains a break" do
      it "can handle that as expected" do
        all = []

        # rubocop:disable Lint/UnreachableLoop
        result = ractorized_object.each_pair do |key, value|
          all << [key, value]
          break 100
        end
        # rubocop:enable Lint/UnreachableLoop

        expect(all).to eq([["foo", "bar"]])
        expect(result).to be(100)
      end
    end

    describe "#inspect" do
      it "is a string" do
        expect(ractorized_object.inspect).to be_a(String)
      end
    end
  end

  describe ".any_thunks?" do
    context "when there are no thunks in the structure" do
      let(:structure) do
        [{ a: Struct.new(:foo).new("bar") }]
      end

      it "is true" do
        expect(structure.first[:a].foo).to eq("bar")
        expect(described_class.any_thunks?(structure)).to be false
      end

      context "when data structure is cyclical" do
        let(:structure) do
          h = { a: Struct.new(:foo).new("bar") }
          h[:h] = h

          [h]
        end

        it "is true" do
          expect(structure.first[:h][:h][:a].foo).to eq("bar")
          expect(described_class.any_thunks?(structure)).to be false
        end
      end
    end

    context "when there are thunks in the structure" do
      let(:structure) do
        bar = Ractorize::Thunk.new(Ractor::Port.new.tap { it << "bar" })

        [{ a: Struct.new(:foo).new(bar) }]
      end

      it "is true" do
        expect(structure.first[:a].foo).to eq("bar")
        expect(described_class.any_thunks?(structure)).to be true
      end

      context "when those thunks are in an object's instance variables" do
        let(:structure) do
          bar = Ractorize::Thunk.new(Ractor::Port.new.tap { it << "bar" })

          a = Object.new
          a.singleton_class.attr_accessor :foo
          a.foo = bar

          [{ a: }]
        end

        it "is true" do
          expect(structure.first[:a].foo).to eq("bar")
          expect(described_class.any_thunks?(structure)).to be true
        end
      end
    end
  end

  context "when a thunk is resolved in a different ractorized object than the one that received it" do
    it "can still resolve the thunk" do
      five = described_class[5]

      thunk = five * 2

      expect(Ractorize::Thunk === thunk).to be true
      expect(thunk).to eq(10)

      ractorized_doubler.set(five * 2)
      ractorized_doubler.double
      result = ractorized_doubler.get

      expect(Ractorize::Thunk === result).to be true

      expect(result.__value__).to eq(20)
    end
  end
end
