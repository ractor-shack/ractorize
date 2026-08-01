# Ractorize

Have an object you wish were a ractor but isn't? Well, this gem lets you ractorize it!

When you ractorize an object, you can just call the normal methods on the object as if it weren't a ractor.
These method calls will automatically be sent as messages to a different ractor where that
object now lives to be executed there concurrently.

## Installation

Typical stuff: add `gem "ractorize"` to your Gemfile or .gemspec file. Or even just
`gem install ractorize` if just playing with it directly in scripts.

## Usage

You can find the full version of this example script in `example_scripts/product`:

```ruby
CONCURRENCY = 3
RANDOM_NUMBERS = 25_000.times.map { BigDecimal(rand * 2.78) }

class Productizer
  attr_accessor :product

  def initialize = self.product = 1
  def multiply(integer) = self.product *= integer
end

def multiply_all(productizer_class)
  productizers = CONCURRENCY.times.map { productizer_class.new }

  RANDOM_NUMBERS.each.with_index do |number, index|
    productizers[index % CONCURRENCY].multiply(number)
  end

  puts productizers.map(&:product).inject(:*)
  puts
end

puts "running non-ractorized productizer"
multiply_all(Productizer)

puts "running ractorized productizer"
multiply_all(Ractorize[Productizer])
```

We turned the Productizer class's instances into ractors by calling `Ractorize[Productizer]`. You can
also ractorize individual objects with `Ractorize[some_object]`.

Notice how, whether it's ractorized or not, we can just use the same exact interface? Fun!

You can find a script that benchmarks these the ractorized versus non-ractorized
approach in `example_scripts/product-benchmark`.

Here's an example run of the product-benchmark script:

```
$ example_scripts/product-benchmark
benchmarking non-ractorized productizer
product is 0.568147e51
took 2.303 seconds

benchmarking ractorized productizer
/home/miles/gitlocal/ractor-shack/ractorize/src/ractorize/ractorized_object.rb:12: warning: Ractor API is experimental and may change in future versions of Ruby.
product is 0.568147e51
took 0.195 seconds

$
```

## Advanced usage/some niceties

### Auto-freeze non-shareable stuff passed to ractorized objects/methods

Not really in the mood to track down all the strings you're sending to your ractorized objects
that happen to be non-shareable due to not being frozen? Or maybe you're in the mood
but don't control the code where they are being initialized? You can just auto-freeze them!

You can use `Ractorize.auto_freeze` for that.

A few flavors:

#### Auto-freezing any instance of a class

Let's just freeze all strings sent to any ractorized object.

```ruby
Ractorize.auto_freeze(String)

h = Ractorize[{}]

key = "foo"
value = "bar"

puts "value frozen? #{value.frozen?}"
h[key] = value
puts "value frozen? #{value.frozen?}"
```

This results in:

```
key frozen? false value frozen? false
key frozen? true value frozen? true
```

#### Only auto-freezing stuff passed to a specific type of ractorized object

You can specify that auto-freezing should only apply to ractorized objects of a specific class.

Let's say you want to freeze stuff passed to ractorized instances of Array but not interfere with
anything ractorized instances of Hash might be doing. You can do this like so:

```ruby
Ractorize.auto_freeze(Array, String)

h = Ractorize[{}]

key = "foo"
value = "bar"

puts "Before Hash#[]= value frozen? #{value.frozen?}"
h[key] = value
puts "After Hash#[]= value frozen? #{value.frozen?}"

a = Ractorize[[]]

a.push(value)
puts "After Array#push value frozen? #{value.frozen?}"
```

This prints out:

```
Before Hash#[]= value frozen? false
After Hash#[]= value frozen? false
After Array#push value frozen? true
```

So only sending the string to an Array resulted in auto-freezing it.

#### programmatically expressing when to auto-freeze

You can also pass a proc to express whether or not to autofreeze an object:

```ruby
Ractorize.auto_freeze(Ractor.shareable_proc { it.is_a?(String) && it =~ /baz/ })

a = Ractorize[[]]

strings = ["foo", "bar", "baz"]

strings.each { a.push(it) }

puts strings.map(&:frozen?).inspect
```

This outputs:

```
[false, false, true]
```

Notice that only the last string, which meets the criteria, was frozen.

### How to move arguments to the receiving ractorized object

You can express that you'd like an argument to be moved to the receiving ractorized object.

This allows you to not have to worry about if the argument is shareable or not.

You will get errors, though, when trying to make use of the moved argument in the calling
code, just like when using ractors directly and moving objects between them.

The interface is identical to `.auto_feeze` but through the method `.move_arg`:

```ruby
class Foo
  def object_id_of(s) = s.object_id
end

foo = Ractorize[Foo.new]
s = "asdf"

puts "calling ractor s.object_id before #push: #{s.object_id}"
puts "object_id in receiving ractor Foo#object_id_of: #{foo.object_id_of(s)}"
puts "s.length in calling ractor: #{s.length}"
puts

puts "Configuring all String instances to be moved to receiving ractor"
puts
Ractorize.move_arg(String)

puts "calling ractor s.object_id before #push: #{s.object_id}"
puts "object_id in receiving ractor Foo#object_id_of: #{foo.object_id_of(s)}"
puts "s.length in calling ractor: #{s.length}"
```

this outputs:

```
calling ractor s.object_id before #push: 896
object_id in receiving ractor Foo#object_id_of: 904
s.length in calling ractor: 4

Configuring all String instances to be moved to receiving ractor

calling ractor s.object_id before #push: 896
object_id in receiving ractor Foo#object_id_of: 896
example_scripts/auto_freeze/move-arg:25:in 'Ractor::MovedObject#method_missing': can not send any methods to a moved object (Ractor::MovedError)
```

Notice that before we configure String to be moved, `foo` receives a copy of `s`, hence the different
object_id.

But once we configure String to be moved, now `foo` receives `s` instead of a copy, hence the object_id
being the same.

However, then when we try to print out the length of `s` in the calling ractor, we get a `Ractor::MovedError`.

## Gotchas

### Predicate methods not ending in "?" in `if/unless/until/while/case/when/in` statements will always return truthy values!

If you try to use the return value of a ractorized object (or any instance of a ractorized class)
in a boolean expression, it will always be truthy!!

You need to instead call `#__value__` on it to force it into the real value. This will make it block, but
that's what you want anyways in such a situation.

Example:

```ruby
class String
  def is_empty = empty?
end

if Ractorize["asdf"].is_empty
  puts "It's empty!"
else
  puts "It's not empty!"
end
```

This will incorrectly print out `It's empty!`! To make it work you can force it to block and wait
for the actual value and use the actual value with the `#__value__` method:

```ruby
class String
  def is_empty = empty?
end

if Ractorize["asdf"].is_empty.__value__
  puts "It's empty!"
else
  puts "It's not empty!"
end
```

This will correctly print out `It's not empty!`.

Note that this isn't necessary with methods ending in "?" as this will automatically block
and return the boolean value.

Also, the predicate methods `==`, `!=` and `!` also will automatically block and return the boolean
value, just like methods ending in "?". So you can freely do `if Ractorize["asdf"] == "asdf"` works
perfectly fine just like predicate methods ending in "?".

### Calling a method on a closed ractorized object might result in a deadlock!

It will usually raise a `Ractor::CloseError` but once in a while it can deadlock.

Note that if you call either `#__close__` or `#__join__` on the object, then the underlying ractor will be closed.

An easy way to avoid the deadlock is just don't make any use of such an object after closing it.

### Objects returned from a method called on a ractorized object might be cloned!

You might have a "void" method where you don't care about the return value but it also doesn't
return `nil` instead it just returns the last expression arbitrarily.

This return value (or parts of it) will be cloned by CRuby/Ractor if it's not shareable!

Confusing stuff can happen with certain types of objects when cloned, such as open files.

## Fine print

Ractors are still experimental and so this gem is also still experimental.
Could be fun to experiment with, though! If you have questions or would like help with this gem, please reach out!

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ractor-shack/ractorize

You can run the linter and test suite locally by cloning this project, running `bundle install` and then
`rake` or `bundle exec rake` if you need it.

## License

This project is licensed under the MPL-2.0 license. Please see LICENSE.txt for more info.
