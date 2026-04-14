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

## Fine print

Ractors are still experimental and so this gem is also still experimental.
Could be fun to experiment with, though! If you have questions or would like help with this gem, please reach out!

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ractor-shack/ractorize

You can run the linter and test suite locally by cloning this project, running `bundle install` and then
`rake` or `bundle exec rake` if you need it.

## License

This project is licensed under the MPL-2.0 license. Please see LICENSE.txt for more info.
