# frozen_string_literal: true

require_relative 'exports'

module RubyCleanCSS

  # Instances should NOT be shared among threads.
  class Compressor

    LIB_PATH = File.expand_path(File.dirname(__FILE__)+'/../javascript')

    MINIFIER_JS_OBJ = 'minifier'
    MINIFY_FUNC = "_#{MINIFIER_JS_OBJ}_minify"

    # On success, `{min: minified_result_string, errors: [], warnings: [...], stats: {...}}`
    # On failure, `{min: nil, errors: [err_msg, ...], warnings: [...], stats: {...}}`
    attr_reader :last_result

    def initialize(options = {})
      @js_options = js_options_from_hash(options)
      setup_minifier
    end

    def compress(stream_or_string)
      @last_result = {min: nil, errors: [], warnings: [], stats: {}}
      @last_result = minify(stream_or_string.to_s)
      @last_result[:min]
    end

    private

      def minify(str)
        js_result = js_runtime.call(MINIFY_FUNC, str)
        {
          min: js_result['styles'],
          errors: js_result['errors'],
          warnings: js_result['warnings'],
          stats: js_result['stats']
        }
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
          let #{MINIFIER_JS_OBJ} = new (require('clean-css/index'))( #{@js_options.to_json} );

          // Function needs to be on global `this` so `MiniRacer::Context#call` will work
          function #{MINIFY_FUNC}(str) {
            let resultData;
            // We need to pass a callback, or CleanCss will behave differently from the original
            //  ruby-clean-css gem regarding `@import`s.
            #{MINIFIER_JS_OBJ}.minify(str, null, (_errs, data) => { resultData = data; });

            return resultData;
          }
        MINIF
      end

      # See README.md for a description of each option, and see
      #   https://github.com/jakubpawlowicz/clean-css#constructor-options
      # for the JS translation.
      #
      # TODO: there aren't adequate tests for these options
      #
      def js_options_from_hash(options)
        js_opts = {
          # enable old clean-css behavior for backward compat
          'inline' => ['all']  # clean-css docs say this is the same as ['local', 'remote'], but local inlining isn't happening without 'all'!
        }

        if options.key?(:keep_special_comments)
          js_opts['specialComments'] = {
            'all' => '*',
            'first' => 1,
            'none' => 0,
            '*' => '*',
            '1' => 1,
            '0' => 0
          }[options[:keep_special_comments].to_s]
        end

        if options[:keep_breaks]
          js_opts['format'] = 'keep-breaks'
        end

        if options.key?(:rebase_to)  # 4.x NOTE: this replaces `root` & `relativeTo`
          js_opts['rebaseTo'] = options[:rebase_to].to_s
        end

        if options.key?(:inline)
          options[:inline].strip.split(/\s*,\s*/).tap do |vals|
            js_opts['inline'] = vals
          end
        end

        if options.key?(:rebase_urls)
          js_opts['rebase'] = options[:rebase_urls] ? true : true
        end

        # `advanced` option was removed. This replaces it, maybe? 
        if options.key?(:level)
          options[:level].tap do |lvl|
            [0, 1, 2].include?(lvl) or raise "Invalid :level #{lvl.inspect}"
            js_opts['level'] = lvl
          end
        end

        if options.key?(:rounding_precision)  # NOTE: 4.x: defaults to no rounding (was 2)
          js_opts['roundingPrecision'] = options[:rounding_precision].to_i
        end

        if options.key?(:compatibility)
          js_opts['compatibility'] = options[:compatibility].to_s
          unless %w[ie7 ie8 ie9 *].include?(js_opts['compatibility'])
            raise(
              'Ruby-Clean-CSS: unknown compatibility setting: '+
              js_opts['compatibility']
            )
          end
        end

        js_opts
      end
  end
end
