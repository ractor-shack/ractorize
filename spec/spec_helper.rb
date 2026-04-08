ENV["FOOBARA_ENV"] = "test"

require "bundler/setup"

if ENV["CI"] != "true"
  if ENV["RUBY_DEBUG"] == "true"
    require "debug"
  elsif ENV["USE_PRY"] == "true"
    require "pry"
  elsif ENV["USE_PRY_BYEBUG"] == "true"
    require "pry"
    require "pry-byebug"
  end
end

require "rspec/its"

require_relative "support/simplecov"

require "ractorize"

RSpec.configure do |config|
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.order = :defined
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.raise_errors_for_deprecations!
end

Dir["#{__dir__}/support/**/*.rb"].each { |f| require f }

require "foobara/spec_helpers/all"
