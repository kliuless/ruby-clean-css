# frozen_string_literal: true

# Attribution: much of this stubbly code is drawn from
# https://github.com/cowboyd/less.rb/blob/master/lib/less/loader.rb
#
# Thanks!
#
# Modified by kliu for MiniRacer


require 'net/http'
require 'pathname'
require 'uri'

module RubyCleanCSS
  # NOTE: these modules are supposed to emulate Node.js modules, but some seem to be out of date -
  #  they don't match the current docs. Perhaps they're a minimal implementation to make clean-css
  #  work.
  module Exports

    class << self
      # js_env: CommonJS::MiniRacerEnv instance
      def define_all_modules(js_env)
        js_env.attach_rb_functions_to_mod_cache('path', self::Path)
        js_env.attach_rb_functions_to_mod_cache('util', self::Util)
        js_env.attach_rb_functions_to_mod_cache('url', self::Url)

        # Attach to top-level object
        # Note: our top-level modules aren't `require`able (but they are in nodejs)
        js_env.attach_rb_functions('console', self::Console)
        js_env.attach_rb_functions('Buffer', self::Buffer)

        define_process_at_toplevel(js_env)
        define_fs_in_cache(js_env)
        define_http_in_cache(js_env)
      end

      private

      # Implemenation note: when using `ctx.eval`, don't pollute the JS top-level with temporary
      # variables; use IIFE.

      def define_process_at_toplevel(js_env)
        ctx = js_env.runtime
        ctx.eval( <<~PROC )
          // define on global object to act like Node
          this.process = {
            nextTick(cb) { cb(); }
          };
        PROC
        ctx.attach('process.cwd', Dir.method(:pwd))
        ctx.attach('process.hrtime',
          (proc {|;init_time|  # the semicolon is intentional, see https://stackoverflow.com/a/33525422
             init_time = Time.now  # Set only once when attaching; doesn't change when hrtime is called
             # This is the proc that gets attached to `hrtime`
             proc {|hrt|
               hrt = hrt || [0,0]
               delta = Time.now - init_time
               [delta.to_i - hrt[0], (delta % 1 * 1000000000).to_i - hrt[1]]
             }
           }).call
        )
        ctx.attach('process.exit', proc {|*args|
          warn("JS process.exit(#{args.first}) called from: \n#{caller.join("\n")}")
        })
        nil
      end

      def define_fs_in_cache(js_env)
        ctx = js_env.runtime
        exports_qname = js_env.attach_rb_functions_to_mod_cache('fs', self::FS)
        ctx.eval( <<~FS , filename: "#{__FILE__}/#{__method__}" )
          ((fs) => {
            'use strict';

            fs.statSync = (path) => {
              let stat = fs._statSyncHelper(path);
              let isFile = fs._isFile(path);
              stat.isFile = () => isFile;
              return stat;
            };

            fs.readFile = (path, encoding, callback) => {
              // 1st callback arg is `err`.
              // Ideally we'd catch errors from _readFile and wrap it an `Error`.
              callback(null, fs._readFile(path));
            };
          })( #{exports_qname} );
        FS
      end

      # Defines both http & https modules
      def define_http_in_cache(js_env)
        ctx = js_env.runtime
        http_exports_qname = js_env.attach_rb_functions_to_mod_cache('http', self::Http)
        https_exports_qname = js_env.define_cached_module('https')

        # (Maybe move most of this JS to a '.js' file to get syntax highlighting)
        ctx.eval( <<~HTTP , filename: "#{__FILE__}/#{__method__}" )
          // same implementation for http & https
          #{https_exports_qname} = #{http_exports_qname};

          ((http) => {  // set a local shortcut to `http`'s exports
            'use strict';
            // Node's `get` can also accept the url as the 1st arg (but clean-css doesn't use that signature).
            http.get = (opts, cb) => {
              let errStr;
              let {body, statusCode, headers} = http._getHelper(opts);
              try {
                cb( new http._IncomingMessage(body, statusCode, headers) );
              } catch(err) {
                errStr = err.toString();
              }
              return new http._ClientRequest(errStr);
            };

            // These classes start with '_' so they're not accidentally used by other JS code.

            // This was called HttpGetResult in original ruby impl
            http._ClientRequest = class {
              constructor(errMsg) { this._errMsg = errMsg; }
              on(event, cb) {
                if (event === 'error' && this._errMsg) {
                  cb(new Error(this._errMsg));
                }
                return this;
              }
              setTimeout(timeoutMs, cb) { /* ignored */ }
            };

            // This was called ServerResponse in original ruby impl
            http._IncomingMessage = class {
              constructor(data, statusCode, headers) {
                this._data = data;
                this.statusCode = statusCode;
                this.headers = headers;
              }
              on(event, cb) {
                if (event === 'data') {
                  cb(this._data);
                } else {
                  cb();
                }
                return this;
              }
            };
          })( #{http_exports_qname} );
        HTTP
      end
    end


    module Console # :nodoc:
      class << self
        def log(*msgs)
          str = build_output(msgs)
          STDOUT.puts(str)
        end
        def error(*msgs)
          str = build_output(msgs)
          STDERR.puts(str)
        end

        alias :warn :error
        alias :info :log

        private

        def build_output(msgs)
          # `to_s` is needed in case a non-string is passed
          if msgs.first.to_s.include?('%')
            # Edge cases:
            # - If there more args than were used in the format specifier, Node.js joins them to the
            #  end after performing sprintf. In our case, the extra args are ignored.
            # - If you try to format a string as a number, Node.js inserts 'NaN', but we will treat
            #  the format as completely invalid (`rescue` case).
            #
            # `sprintf` will raise on invalid format specifier
            sprintf(*msgs)  rescue msgs.join(' ')
          else
            msgs.join(' ')
          end
        end
      end
    end


    module Path # :nodoc:
      class << self
        def join(*components)
          # node.js expands path on join
          File.expand_path(File.join(*components))
        end

        def dirname(path)
          File.dirname(path)
        end

        def resolve(path)
          File.expand_path(path)
        end

        def relative(base, path)
          Pathname.new(path).relative_path_from(Pathname.new(base)).to_s
        end
      end
    end


    # NOTE: in Node.js, this is deprecated in favor of `console`
    module Util # :nodoc:
      def self.error(*errors)
        errors.each { |err| STDERR.puts(err) } ; nil
      end

      def self.puts(*args)
        args.each { |arg| STDOUT.puts(arg) } ; nil
      end
    end


    # See `define_fs_in_cache` for remaining impl
    module FS # :nodoc:
      # When changing this attr list, make sure the attr values will auto-convert to sensible JS values.
      # Ruby `Time`s (e.g. `mtime`) are auto-converted to JS `Date`s, even when nested in a hash.
      ATTRS = %i[dev ino mode nlink uid gid rdev size blksize blocks
                 atime mtime ctime birthtime].freeze

      class << self
        def _statSyncHelper(path)
          stat = File.stat(path)
          Hash.new.tap do |h|
            ATTRS.each do |attr|
              h[attr] = stat.public_send(attr)
            end
          end
        end

        def _isFile(path)
          File.file?(path)
        end

        def existsSync(path)
          File.exists?(path)
        end

        def _readFile(path)
          File.read(path)
        end

        def readFileSync(path, encoding = nil)
          IO.read(path)
        end
      end
    end


    class Buffer # :nodoc:
      def self.isBuffer(data)
        false
      end
    end


    module Url # :nodoc:
      def self.resolve(*args)
        # Note: The original ruby-clean-css didn't have `to_s`, even though `resolve` is supposed to
        #  return a string. How did that actually work?
        URI.join(*args).to_s
      end

      def self.parse(url_string)
        u = URI.parse(url_string)
        result = {}
        result['protocol'] = u.scheme+':'  if u.scheme
        result['auth'] = (u.user || u.password)  ?  "#{u.user}:#{u.password}"  :  ''
        if u.host
          result['hostname'] = u.host
          result['host'] = "#{u.host}#{ ":#{u.port}" if u.port }"
        end
        result['pathname'] = u.path         if u.path
        result['path']     = u.request_uri  if u.respond_to?(:request_uri)
        result['port']     = u.port         if u.port
        if u.query
          result['query'] = u.query
          result['search'] = '?'+u.query
        end
        result['hash'] = '#'+u.fragment  if u.fragment
        result['href'] = u.to_s
        result
      end
    end


    module Http # :nodoc:
      def self._getHelper(options)
        err = nil
        uri_hash = {}
        uri_hash[:host] = options['hostname'] || options['host']
        path = options['path'] || options['pathname'] || ''
        # We do this because node expects path and query to be combined:
        path_components = path.split('?', 2)
        if path_components.length > 1
          uri_hash[:path] = path_components[0]
          uri_hash[:query] = path_components[0]
        else
          uri_hash[:path] = path_components[0]
        end
        uri_hash[:port] = options['port'] ? options['port'] : Net::HTTP.http_default_port
        # We check this way because of node's http.get:
        uri_hash[:scheme] = uri_hash[:port] == Net::HTTP.https_default_port ? 'https' : 'http'
        case uri_hash[:scheme]
        when 'http'
          uri = URI::HTTP.build(uri_hash)
        when 'https'
          uri = URI::HTTPS.build(uri_hash)
        else
          # NOTE: in the original ruby-clean-css, this raises Exception, which propagated to ruby as a V8::Error. We can't do that with MiniRacer, which propagates the original ruby error, so we raise StandardError.
          raise(StandardError, 'import only supports http and https')
        end

        response =
          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
            # 'identity' disables net/http's auto-compression, so Content-Length will be correct.
            http.get(uri.request_uri, {'Accept-Encoding' => 'identity'})
          end

        # Net::HTTP auto-normalizes header names to lowercase, just like Node.js
        flat_headers = Hash.new.tap do |h|
          response.to_hash.each {|k, v_arr| h[k] = v_arr.first }
        end

        { body:       response.read_body,
          statusCode: response.code.to_i,
          headers:    flat_headers }
      end
    end

  end
end
