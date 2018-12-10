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

      # Copy of the JS options as seen by the underlying clean-css instance, to troubleshoot the
      #  translation of ruby options to JS. Should only be called after `setup_minifier`.
      def native_options
        js_runtime.eval("#{MINIFIER_JS_OBJ}.options")
      end

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
      def js_options_from_hash(options)
        js_opts = {
          # enable old clean-css behavior for backward compat
          'inline' => ['all'],  # clean-css docs say this is the same as ['local', 'remote'], but local inlining isn't happening without 'all'!
          # Backward compat: enable optimization levels 1 & 2 with default sub-options.
          # Note: we don't use `{2 => {'all' => true}}` because some level 2 options default to
          #  `false`.
          'level' => {1 => {}, 2 => {}}
        }

        if options.key?(:keep_special_comments)
          js_opts['level'][1]['specialComments'] = {
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

        if options.key?(:inline)
          options[:inline].tap do |val|
            raise TypeError, ":inline must be a String"  unless val.is_a?(String)
            js_opts['inline'] = [val]
          end
        end

        if options.key?(:rebase_urls)
          js_opts['rebase'] = options[:rebase_urls] ? true : false
        end

        if options.key?(:rebase_to)  # 4.x NOTE: this replaces `root` & `relativeTo`
          js_opts['rebaseTo'] = options[:rebase_to].to_s
        end

        if options.key?(:rounding_precision)  # NOTE: 4.x: defaults to no rounding (was 2)
          js_opts['level'][1]['roundingPrecision'] = options[:rounding_precision].to_i
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
