# frozen_string_literal: true

require_relative 'exports'

module RubyCleanCSS

  # Instances should NOT be shared among threads.
  class Compressor

    LIB_PATH = File.expand_path(File.dirname(__FILE__)+'/../javascript')

    MINIFIER_JS_OBJ = 'minifier'
    MINIFY_FUNC = "_#{MINIFIER_JS_OBJ}_minify"

    # On success, `{min: minified_result_string, errors: [], warnings: []}`
    # On failure, `{errors: [err_msg, ...], warnings: [warn_msg, ...]}`
    attr_reader :last_result

    def initialize(options = {})
      @js_options = js_options_from_hash(options)
      setup_minifier
    end

    def compress(stream_or_string)
      @last_result = result = {min: nil, errors: [], warnings: []}
      begin
        # This may raise an error
        result[:min] = minify(stream_or_string.to_s)
      ensure
        result[:errors] = get_errors
        result[:warnings] = get_warnings
      end
      result[:min]
    end

    private

      def minify(str)
        js_runtime.call(MINIFY_FUNC, str)
      end

      def js_runtime
        @js_runtime ||= MiniRacer::Context.new
      end

      def js_env
        unless @js_env
          @js_env = CommonJS::MiniRacerEnv.new(js_runtime, path: LIB_PATH)
          RubyCleanCSS::Exports.define_all_modules(@js_env)
        end
        @js_env
      end

      def setup_minifier
        js_env  # ensure this is initialized

        js_runtime.eval( <<~MINIF, filename: "#{__FILE__}/#{__method__}" )
          let #{MINIFIER_JS_OBJ} = require('clean-css/index')( #{@js_options.to_json} );

          // Function needs to be on global `this` so `MiniRacer::Context#call` will work
          function #{MINIFY_FUNC}(str) {
            let resultStr;
            // We need to pass a callback, or CleanCss will behave differently from the original
            //  ruby-clean-css gem regarding `@import`s.
            #{MINIFIER_JS_OBJ}.minify(str, ( _errs, data) => { resultStr = data; });
            return resultStr;
          }
        MINIF
      end

      def get_errors
        js_runtime.eval("#{MINIFIER_JS_OBJ}.context.errors")
      end
      def get_warnings
        js_runtime.eval("#{MINIFIER_JS_OBJ}.context.warnings")
      end

      # See README.md for a description of each option, and see
      # https://github.com/GoalSmashers/clean-css#how-to-use-clean-css-programmatically
      # for the JS translation.
      #
      def js_options_from_hash(options)
        js_opts = {}

        if options.has_key?(:keep_special_comments)
          js_opts['keepSpecialComments'] = {
            'all' => '*',
            'first' => 1,
            'none' => 0,
            '*' => '*',
            '1' => 1,
            '0' => 0
          }[options[:keep_special_comments].to_s]
        end

        if options.has_key?(:keep_breaks)
          js_opts['keepBreaks'] = options[:keep_breaks] ? true : false
        end

        if options.has_key?(:root)
          js_opts['root'] = options[:root].to_s
        end

        if options.has_key?(:relative_to)
          js_opts['relativeTo'] = options[:relative_to].to_s
        end

        if options.has_key?(:process_import)
          js_opts['processImport'] = options[:process_import] ? true : false
        end

        if options.has_key?(:no_rebase)
          js_opts['noRebase'] = options[:no_rebase] ? true : false
        elsif !options[:rebase_urls].nil?
          js_opts['noRebase'] = options[:rebase_urls] ? false : true
        end

        if options.has_key?(:no_advanced)
          js_opts['noAdvanced'] = options[:no_advanced] ? true : false
        elsif !options[:advanced].nil?
          js_opts['noAdvanced'] = options[:advanced] ? false : true
        end

        if options.has_key?(:rounding_precision)
          js_opts['roundingPrecision'] = options[:rounding_precision].to_i
        end

        if options.has_key?(:compatibility)
          js_opts['compatibility'] = options[:compatibility].to_s
          unless ['ie7', 'ie8'].include?(js_opts['compatibility'])
            raise(
              'Ruby-Clean-CSS: unknown compatibility setting: '+
              js_opts['compatibility']
            )
          end
        end

        if options.has_key?(:benchmark)
          js_opts['benchmark'] = options[:benchmark] ? true : false
        end

        if options.has_key?(:debug)
          js_opts['debug'] = options[:debug] ? true : false
        end

        js_opts
      end
  end
end
