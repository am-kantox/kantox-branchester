# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'kantox/branchester/version'

Gem::Specification.new do |spec|
  spec.name          = 'kantox-branchester'
  spec.version       = Kantox::Branchester::VERSION
  spec.authors       = ['Kantox LTD']
  spec.email         = ['aleksei.matiushkin@kantox.com']

  spec.summary       = 'This app assures that my git branch has no merge conflicts with others in the repo.'
  spec.description   = 'Install this gem and a respective local git-hook to get warned when your commits has a merge issues against all the remote branches.'
  spec.homepage      = 'http://kantox.com'
  spec.license       = 'MIT'

  if spec.respond_to?(:metadata)
#    spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'"
  else
    raise 'RubyGems 2.0 or newer is required to protect against public gem pushes.'
  end

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(/^(test|spec|features)\//) }
  spec.bindir        = 'bin'
  spec.executables   = spec.files.grep(/^exe\//) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'ruby-git', '~> 0.2'

  spec.add_development_dependency 'bundler', "~> 1.10"
  spec.add_development_dependency 'rake', "~> 10.0"
  spec.add_development_dependency 'rspec', '~> 3.2'

  spec.add_development_dependency 'pry', '~> 0.10'  
end
