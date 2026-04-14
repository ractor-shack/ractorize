require_relative "version"

Gem::Specification.new do |spec|
  spec.name = "ractorize"
  spec.version = Ractorize::VERSION
  spec.authors = ["Miles Georgi"]
  spec.email = ["azimux@gmail.com"]

  spec.summary = "Turn objects into ractors with ease!"
  spec.homepage = "https://github.com/ractor-shack/ractorize"
  spec.license = "MPL-2.0"
  spec.required_ruby_version = Ractorize::MINIMUM_RUBY_VERSION

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir[
    "lib/**/*",
    "src/**/*",
    "LICENSE*.txt",
    "README.md",
    "CHANGELOG.md"
  ]

  spec.require_paths = ["lib"]
  spec.metadata["rubygems_mfa_required"] = "true"
end
