RSpec.describe Ractorize::GarbageCollection do
  context "when a thunk is garbage collected before it is resolved" do
    it "has its ractor closed" do
      stub_class("SomeClass") do
        def wait_ractor = @wait_ractor = BaseRactor.new { receive }

        def foo
          @wait_ractor.join
          @wait_ractor = nil
          "foo"
        end
      end

      some_object = Ractorize[SomeClass].new
      expect(some_object).to be_a(SomeClass)
      wait_ractor = some_object.wait_ractor
      some_object.foo
      some_object = nil # rubocop:disable Lint/UselessAssignment
      GC.start
      GC.start
      wait_ractor << 1
      wait_ractor = nil # rubocop:disable Lint/UselessAssignment
      nil
      # not sure how best to test this hmmm... however the ractor_leaks.rb file will catch it if it
      # doesn't work.
    end
  end
end
