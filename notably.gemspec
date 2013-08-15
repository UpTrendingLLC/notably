# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'notably/version'

Gem::Specification.new do |spec|
  spec.name          = "notably"
  spec.version       = Notably::VERSION
  spec.authors       = ["Will Cosgrove"]
  spec.email         = ["will@willcosgrove.com"]
  spec.description   = %q{A redis backed notification system}
  spec.summary       = %q{A redis backed notification system}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
end
