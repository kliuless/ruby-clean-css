# frozen_string_literal: true
require 'action_controller/railtie'
require_relative 'sprockets'

module RubyCleanCSS
  class Railtie < ::Rails::Railtie
    initializer(
      'ruby-clean-css.environment',
      :after => 'sprockets.environment'
    ) { |app|
      RubyCleanCSS::Sprockets.register(app.assets)
    }

    initializer(
      'ruby-clean-css.setup',
      :after => :setup_compression,
      :group => :all
    ) { |app|
      if app.config.assets.enabled
        curr = app.config.assets.css_compressor
        unless curr.respond_to?(:compress)
          app.config.assets.css_compressor = RubyCleanCSS::Sprockets::LABEL
        end
      end
    }
  end
end
