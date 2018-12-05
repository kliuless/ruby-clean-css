# -*- encoding: utf-8 -*-
require File.expand_path('../lib/ruby_clean_css/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors = ['Joseph Pearson', 'Kelvin Liu']
  gem.description = 'A Ruby interface to the Clean-CSS minifier for Node.'
  gem.summary = 'Clean-CSS for Ruby.'
  gem.homepage = 'https://github.com/tribune/ruby-clean-css'
  gem.files = `git ls-files`.split($\)
  gem.executables = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files = gem.files.grep(%r{^test/})
  gem.name = 'ruby-clean-css'
  gem.require_paths = ['lib']
  gem.version = RubyCleanCSS::VERSION
  gem.add_dependency('commonjs-mini_racer_env')
  gem.add_development_dependency('rake')
  gem.add_development_dependency('webmock')
  gem.add_development_dependency('minitest')
  gem.add_development_dependency('test-unit')

  # Append all submodule files to the list of gem files.
  gem_dir = File.expand_path(File.dirname(__FILE__)) + "/"
  `git submodule --quiet foreach pwd`.split($\).each { |submodule_path|
    Dir.chdir(submodule_path) {
      submodule_relative_path = submodule_path.sub gem_dir, ""
      `git ls-files`.split($\).each { |filename|
        gem.files << "#{submodule_relative_path}/#{filename}"
      }
    }
  }
end
