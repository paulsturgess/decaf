require_relative '../lib/decaf'

describe Decaf::Rewriter do
  let(:buffer) { Parser::Source::Buffer.new('(string)') }
  let(:ast) { Parser::CurrentRuby.parse(buffer.source) }
  let(:rewriter) { Decaf::Rewriter.new }
  let(:result) { rewriter.rewrite(buffer, ast) }
  before { buffer.source = source }

  describe "stubs" do
    let(:source) { "subject.stubs(:yes)" }

    it "converts to allow to receive" do
      expect(result).to eq(
        "allow(subject).to receive(:yes)"
      )
    end
  end

  describe "stubs with old hash" do
    let(:source) { "subject.stubs(:persisted? => true)" }

    it "converts to allow to receive and return" do
      expect(result).to eq(
        "allow(subject).to receive(:persisted?) { true }"
      )
    end
  end

  describe "stubs with new hash" do
    let(:source) { "subject.stubs(persisted?: true)" }

    it "converts to allow to receive and return" do
      expect(result).to eq(
        "allow(subject).to receive(:persisted?) { true }"
      )
    end
  end

  describe "stubs with no parens" do
    let(:source) { "subject.stubs fares: []" }

    it "converts to allow to receive and return" do
      expect(result).to eq(
        "allow(subject).to receive(:fares) { [] }"
      )
    end
  end

  describe "expects with" do
    let(:source) { "subject.expects(:foo).with(:bar, baz)" }

    it "converts to expect to receive with" do
      expect(result).to eq(
        "expect(subject).to receive(:foo).with(:bar, baz)"
      )
    end
  end

  describe "expects with no args and returns" do
    let(:source) { "Foo.expects(:new).with().returns(bar)" }

    it "converts to expect receive and return" do
      expect(result).to eq(
        "expect(Foo).to receive(:new) { bar }"
      )
    end
  end

  describe "stubs and returns without parens" do
    let(:source) {
      "subject.stubs(:plan_provider_names).returns [:SilverRail, :DBahn]"
    }

    it "converts" do
      expect(result).to eq(
        "allow(subject).to receive(:plan_provider_names) { [:SilverRail, :DBahn] }"
      )
    end
  end

  describe "stubs and returns with parens" do
    let(:source) {
      %q(before do
        Foo.any_instance.stubs(:bar).returns(:baz)
      end)
    }

    it "converts" do
      expect(result).to eq(
        %q(before do
        allow_any_instance_of(Foo).to receive(:bar) { :baz }
      end)
      )
    end
  end

  describe "multiline expects and returns" do
    let(:source) do
      "Foo" \
        ".expects(:bar)" \
        ".returns([ 1,2,3 ])"
    end

    it "converts to expect receive and return" do
      expect(result).to eq(
        "expect(Foo).to receive(:bar) { [ 1,2,3 ] }"
      )
    end
  end

  describe "allow and multiline returns" do
    let(:source) do
      "BankTransferFee.stubs(:for_transaction).returns(" \
        "Money.zero," \
        "Money.new(50, 'GBP')" \
      ")"
    end

    it "converts to allow and receive" do
      expect(result).to eq(
        "allow(BankTransferFee).to receive(:for_transaction) { [Money.zero, Money.new(50, 'GBP')] }"
      )
    end
  end

  describe "multiline stubs" do
    let(:source) do
      %q(user.stubs(
        created_at: Time.utc(2017, 11, 7, 8)
      ))
    end

    it "converts to receive" do
      expect(result).to eq(
        %q(allow(user).to receive(:created_at) {
          Time.utc(2017, 11, 7, 8)
        })
      )
    end
  end

  describe "multiline stubs any instance" do
    let(:source) do
      %q(MyClass.any_instance.stubs(
        foo: 'bar'
      ))
    end

    it "converts to receive" do
      expect(result).to eq(
        %q(allow_any_instance_of(MyClass).to receive(:foo) {
          'bar'
        })
      )
    end
  end

  describe "stubs hash" do
    let(:source) do
      "subject.data.stubs(things: { foo: 'bar' }, some_id: 1, other_id: 2)"
    end

    it "converts to receive_messages" do
      expect(result).to eq(
        "allow(subject.data).to receive_messages(things: { foo: 'bar' }, some_id: 1, other_id: 2)"
      )
    end
  end

  describe "stubs hash multiline" do
    let(:source) do
      "subject.data.stubs(" \
        "things: { foo: 'bar' }," \
        "some_id: 1," \
        "other_id: 2" \
      ")"
    end

    it "converts to receive_messages" do
      expect(result).to eq(
        "allow(subject.data).to receive_messages(" \
          "things: { foo: 'bar' }," \
          "some_id: 1," \
          "other_id: 2" \
        ")"
      )
    end
  end

  describe "never" do
    let(:source) { "subject.expects(:foo).never" }

    it "converts to expect not to receive" do
      expect(result).to eq(
        "expect(subject).to_not receive(:foo)"
      )
    end
  end

  describe "non processable never" do
    let(:source) { "expect_some_method.never" }

    it "does not convert" do
      expect(result).to eq("expect_some_method.never")
    end
  end

  describe "stub" do
    let(:source) { "let(:foo) { stub }" }

    it "converts a stub to a double" do
      expect(result).to eq("let(:foo) { double }")
    end
  end

  describe "stub with methods" do
    let(:source) { "let(:foo) { stub(bar: 'baz') }" }

    it "converts a stub with methods to a double" do
      expect(result).to eq("let(:foo) { double(bar: 'baz') }")
    end
  end

  describe "any instance" do
    let(:source) { "SomeClass.any_instance.stubs(foo?: false)" }

    it "converts to allow_any_instance_of" do
      expect(result).to eq("allow_any_instance_of(SomeClass).to receive(:foo?) { false }")
    end
  end

  describe "expect return stub" do
    let(:source) { "SomeClass.expects(:call).with(foo, bar).returns(stub(success?: true))" }

    it "converts to returning a double" do
      expect(result).to eq(
        "expect(SomeClass).to receive(:call).with(foo, bar) { double(success?: true) }"
      )
    end
  end

  describe "stub return implicit hash" do
    let(:source) { "foo.stubs(:bar).returns(sort: 'email')" }

    it "converts to allow receive" do
      expect(result).to eq(
        "allow(foo).to receive(:bar) { { sort: 'email' } }"
      )
    end
  end

  describe "stub return explicit hash" do
    let(:source) { "foo.stubs(:bar).returns({})" }

    it "converts to allow receive" do
      expect(result).to eq(
        "allow(foo).to receive(:bar) { {} }"
      )
    end
  end

  describe "stub return implicit array" do
    let(:source) { "foo.stubs(:bar).returns(1, 2)" }

    it "converts to allow receive" do
      expect(result).to eq(
        "allow(foo).to receive(:bar) { [1, 2] }"
      )
    end
  end

  describe "multiple return responses" do
    let(:source) { "Foo.stubs(:get).returns(['bar']).then.returns(['baz'])" }

    it "does not process" do
      expect(result).to eq(source)
    end
  end


  describe "returns mock" do
    let(:source) { "Foo.expects(:bar).returns(mock(baz: true))" }

    it "changes the mock for a double" do
      expect(result).to eq("expect(Foo).to receive(:bar) { double(baz: true) }")
    end
  end

  describe "stubs returns stub" do
    let(:source) { "Foo.any_instance.stubs(bar: stub(baz: true))" }

    it "returns a double" do
      expect(result).to eq("allow_any_instance_of(Foo).to receive(:bar) { double(baz: true) }")
    end
  end

  describe "expects with never" do
    let(:source) { "Foo.expects(:delay).with(anything, 'FizzBuzz').never" }

    it "converts to_not receive with" do
      expect(result).to eq("expect(Foo).to_not receive(:delay).with(anything, 'FizzBuzz')")
    end
  end

  describe "expect raises error" do
    # let(:source) { "subject.expects(:foo).raises(error)" }
    let(:source) { "expect(subject).to receive(:foo).raises(error)" }

    it "converts to raise error" do
      expect(result).to eq("expect(subject).to receive(:foo) { raise error }")
    end
  end
end
