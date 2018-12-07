
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "toodeloo/version"

Gem::Specification.new do |spec|
  spec.name          = "toodeloo"
  spec.version       = Toodeloo::VERSION
  spec.authors       = ["Robert Schulze"]
  spec.email         = ["robert@dotless.de"]

  spec.summary       = %q{Toodeloo! allows long running processes to gracefully handle kill signals}
  spec.description   = %q{Toodeloo! allows long running processes to gracefully handle kill signals}
  spec.homepage      = "https://gitbub.com/fnordfish/toodeloo"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features|bin)/})
  end
  # spec.bindir        = "exe"
  # spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", ">= 1.16"
  spec.add_development_dependency "rake", ">= 10.0"
  spec.add_development_dependency "rspec", "~> 3.8"
end
