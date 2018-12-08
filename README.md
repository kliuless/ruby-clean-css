# Ruby-Clean-CSS compressor

This gem provides a Ruby interface to the
[Clean-CSS](https://github.com/jakubpawlowicz/clean-css) Node library for
minifying CSS files.

Ruby-Clean-CSS provides more up-to-date and compatible minification of
stylesheets than the [YUI
compressor](https://github.com/sstephenson/ruby-yui-compressor) (which was
[discontinued](http://www.yuiblog.com/blog/2012/10/16/state-of-yui-compressor)
by Yahoo in 2012)\*.


## Installation

It's a gem, so:

    $ gem install ruby-clean-css


## Usage

You can use this library with Rails, or with Sprockets in non-Rails projects,
or as a standalone library.


### As a plain Ruby library:

Here's the simplest thing that could possibly work:

    >> require 'ruby_clean_css'
    >> RubyCleanCSS::Compressor.new.compress('a { color: chartreuse; }')
    => "a{color:#7fff00}"


### With Sprockets:

You can register the Compressor as Sprocket's default CSS compressor like this:

    require 'ruby_clean_css'
    require 'ruby_clean_css/sprockets'
    RubyCleanCSS::Sprockets.register(sprockets_env)


### With Rails 3 or Rails 4:

Just add this gem to the `:assets` group of your `Gemfile`. Ruby-Clean-CSS
will automatically become the default compressor for CSS files.

If you prefer, you can make it explicit in `config/environments/production.rb`:

    config.assets.css_compressor = :cleancss

Alternatively, if you want to customize the compressor with options,
you can assign an instance of the compressor to that setting:

    config.assets.css_compressor = RubyCleanCSS::Compressor.new(
      rebase_urls: false,
      keep_breaks: true
    )


## Options

This library supports the following [Clean-CSS
options](https://github.com/jakubpawlowicz/clean-css#constructor-options):

- `keep_special_comments` - A "special comment" is one that begins with `/*!`.
    You can keep them all with `:all`, just the first with `:first`, or
    remove them all with `:none`. The default is `:all`.
- `keep_breaks` - By default, all linebreaks are stripped. Set to `true` to
    retain them.
- `rebase_to` - This is the path used to resolve `@import` rules and rebase
    relative URLs. A string. Defaults to the present working directory.
- `inline` - By default, stylesheets included via `@import` are fetched
    and minified inline. Set to 'none' to retain `@import` lines unmodified.
- `rebase_urls` - By default, all URLs are rebased to the root. Set to `false`
    to prevent rebasing.
- `level` - Optimization level. 0 is lowest, 2 is highest. Default is 1.
- `rounding_precision` - The rounding precision on measurements in your CSS.
    An integer, defaulting to `-1` (no rounding).
- `compatibility` - Use this to force Clean-CSS to be compatible with `ie7`,
    `ie8`, `ie9`, or `*` (ie10+). Default is `*`. Supply as a symbol (`:ie7`) or
    string (`'ie7'`).

In keeping with the Node library's interface, there are some synonyms available:

- `:keep_special_comments` has an alternative syntax: `'*'` means  `:all`,
    `1` means `:first` and `0` means `:none`.


## Rails local precompilation (reducing production dependencies)

This is only relevant if a) you're using Rails and b) you always do local
asset precompilation.

V8 is a significant dependency to add to production servers just to
minimise some code. That doesn't seem to bother most people, but if (like me)
you zealously weed out unnecessary dependencies, you may prefer to do
your asset precompilation on your dev machine (or a build server or similar).
In this case, you don't want to add the gem to the `:assets` group in your
Gemfile. You want it in the `:development` group — gems in this group are
not typically bundled onto production servers.

Having done that, there may be another step before Rails will use
Ruby-Clean-CSS for asset compression. Create `lib/tasks/assets.rake` and
add this code:

    namespace(:assets) do
      task(:environment) do
        require('ruby_clean_css')
        require('ruby_clean_css/sprockets')
        RubyCleanCSS::Sprockets.register(Rails.application.assets)
        Rails.application.config.assets.css_compressor = :cleancss
      end
    end

That's it. You don't need to change any practices. `rake assets:precompile`
will now work like you expect.


## \* Why this alternative?

The YUI CSS compressor has been a faithful servant for years. But there are
a few things it muddles up. The one that got me started was this:

    -moz-transition: all 0s linear 200ms;

Which the YUI compressor rewrites to:

    -moz-transition:all 0 linear 200ms;

Mozilla won't parse that, because `0` is not a valid time value. You may have
encountered other little gotchas, like `background:none` being erroneously
shortened to `background:0` and so on. In my testing, Clean-CSS produces a
higher fidelity compression in these areas. (Here's a handy online tool for
comparative testing: http://gpbmike.github.io/refresh-sf/)

Beyond that, Clean-CSS has some useful features around automatic inlining of
`@import` statements, and rebasing of URLs to a common root.

One final rationale is dependencies. Presumably you're also doing JS
minification, and these days you're probably using a JavaScript library
running on a JS VM to do it (Uglify, CoffeeScript, etc). Needing to install
and run a full Java VM purely for CSS minification is arguably wasteful —
it seems better to crush your styles the same way you crush the behavior.


## Contributing

Pull requests are welcome. Please supply a test case with your PR.

## License

Ruby-Clean-CSS is released under the [MIT
Licence](https://github.com/tribune/ruby-clean-css/blob/master/LICENSE).
