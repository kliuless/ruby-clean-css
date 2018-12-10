# -*- encoding: utf-8 -*-
require 'English'
require File.expand_path('../lib/ruby_clean_css/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors = ['Joseph Pearson', 'Kelvin Liu']
  gem.description = 'A Ruby interface to the Clean-CSS minifier for Node.'
  gem.summary = 'Clean-CSS for Ruby.'
  gem.homepage = 'https://github.com/tribune/ruby-clean-css'
  gem.files = `git ls-files`.split($RS)
  gem.executables = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files = gem.files.grep(%r{^test/})
  gem.name = 'ruby-clean-css'
  gem.require_paths = ['lib']
  gem.version = RubyCleanCSS::VERSION

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if gem.respond_to?(:metadata)
    gem.metadata["allowed_push_host"] = "PUSH_DISABLED"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  gem.add_dependency('commonjs-mini_racer_env', '~> 0.3.0')
  gem.add_development_dependency('rake')
  gem.add_development_dependency('webmock')
  gem.add_development_dependency('minitest')
  gem.add_development_dependency('test-unit')

  # Append all submodule files to the list of gem files.
  gem_dir = File.expand_path(File.dirname(__FILE__)) + "/"
  `git submodule --quiet foreach pwd`.split($RS).each { |submodule_path|
    Dir.chdir(submodule_path) {
      submodule_relative_path = submodule_path.sub gem_dir, ""
      `git ls-files`.split($RS).each { |filename|
        gem.files << "#{submodule_relative_path}/#{filename}"
      }
    }
  }
end
