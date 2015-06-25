$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "erb_safety/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "erb_safety"
  s.version     = ErbSafety::VERSION
  s.authors     = ["Francois Chagnon"]
  s.email       = ["francois.chagnon@shopify.com"]
  s.homepage    = "https://github.com/Shopify/erb_safety"
  s.summary     = "Asserts the safety of ERB interpolations"
  s.description = "Parses out ERB out of HTML and makes assertions on the safety of interpolated ruby code."
  s.license     = "MIT"

  s.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.rdoc"]
  s.test_files = Dir["test/**/*"]

  s.add_development_dependency 'rake'
end
