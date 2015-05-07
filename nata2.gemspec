# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'nata2/version'

Gem::Specification.new do |spec|
  spec.name          = 'nata2'
  spec.version       = Nata2::VERSION
  spec.authors       = ['studio3104']
  spec.email         = ['studio3104.com@gmail.com']
  spec.summary       = %q{Analyzer of MySQL slow query log}
  spec.description   = %q{Analyzer of MySQL slow query log}
  spec.homepage      = ''
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 1.5'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'webmock'
  spec.add_runtime_dependency 'sinatra'
  spec.add_runtime_dependency 'sinatra-contrib'
  spec.add_runtime_dependency 'slim', '= 2.0.2'
  spec.add_runtime_dependency 'toml'
  spec.add_runtime_dependency 'sequel'
  spec.add_runtime_dependency 'sqlite3'
  spec.add_runtime_dependency 'mysql2'
  spec.add_runtime_dependency 'focuslight-validator'
  spec.add_runtime_dependency 'thor'
end
