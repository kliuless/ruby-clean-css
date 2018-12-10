# frozen_string_literal: true
require('test/unit')
require('webmock/minitest')
require('ruby-clean-css')

class RubyCleanCSS::TestCompressor < Test::Unit::TestCase

  def test_compression
    assert_equal('a{color:#7fff00}', compress('a { color: chartreuse; }'))
  end


  def test_option_to_keep_breaks
    # Confirm that breaks aren't kept by default
    parts = ['a{color:#7fff00}','b{font-weight:900}']
    assert_equal(
      parts.join,
      compress(parts.join("\n"))
    )

    # ... then confirm that breaks are kept when the option is set to true.
    parts = ['a{color:#7fff00}','b{font-weight:900}']
    assert_equal(
      parts.join("\n"),
      compress(parts.join("\n"), keep_breaks: true)
    )
  end


  def test_rounding_precision  # level 1
    # Default: no rounding
    assert_equal('a{font-size:12.345px}', compress('a { font-size: 12.345px; }'))
    # Custom rounding
    assert_equal('a{font-size:12.3px}',
                 compress('a { font-size: 12.345px; }', rounding_precision: 1))
  end


  def test_keep_special_comments  # level 1
    input = 'a { color: chartreuse; } /*! special comment 1 */ p { font-weight:700; } /*! special comment 2 */'

    # Default: keep all
    assert_equal(
      'a{color:#7fff00}/*! special comment 1 */p{font-weight:700}/*! special comment 2 */',
      compress(input)
    )

    # keep first
    assert_equal(
      'a{color:#7fff00}/*! special comment 1 */p{font-weight:700}',
      compress(input, keep_special_comments: 'first')
    )

    # keep none
    assert_equal(
      'a{color:#7fff00}p{font-weight:700}',
      compress(input, keep_special_comments: 'none')
    )
  end


  def test_merge_adjacent  # level 2 should be enabled by default
    assert_equal('a{color:#7fff00;font-weight:700}',
                 compress('a { color: chartreuse; } a { font-weight: bold; }'))
  end


  def test_local_import_processing
    local_path = 'test/foo.css'
    input = (<<~INP)
      @import url(#{local_path});
      a {
        color: chartreuse;
      }
    INP
    inlined_output = 'b{font-weight:900}a{color:#7fff00}'
    non_inlined_output = "@import url(#{local_path});a{color:#7fff00}"

    File.open(local_path, 'w') { |f|
      f << 'b { font-weight: 900; }'
    }
    # Default: inline all imports (including local)
    assert_equal( inlined_output, compress(input) )
    # Do inline - import is local
    assert_equal( inlined_output, compress(input, inline: 'local') )

    # Don't inline anything
    assert_equal( non_inlined_output, compress(input, inline: 'none') )
    # Don't inline - import isn't remote. Note that this will trigger a clean-css warning.
    assert_equal( non_inlined_output, compress(input, inline: 'remote') )
  ensure
    File.unlink(local_path)  if File.exist?(local_path)
  end


  def test_remote_import_processing
    url = 'http://ruby-clean-css.test/foo.css'
    input = "@import url(#{url}); b{ font-weight:900 }"
    inlined_output = 'a{color:#7fff00}b{font-weight:900}'
    non_inlined_output = "@import url(#{url});b{font-weight:900}"

    WebMock.stub_request(:get, url).to_return(body: 'a { color: chartreuse; }')
    # Default: inline all imports (including remote)
    assert_equal( inlined_output, compress(input) )
    # Do inline - import is remote
    assert_equal( inlined_output, compress(input, inline: 'remote') )

    # Don't inline anything
    assert_equal( non_inlined_output, compress(input, inline: 'none') )
    # Don't inline - import isn't local. Note that this will trigger a clean-css warning.
    assert_equal( non_inlined_output, compress(input, inline: 'local') )
  end


  def test_url_rebasing
    local_import_path = 'test/foo.css'
    local_image_path = '../images/lenna.jpg'
    File.open(local_import_path, 'w') { |f|
      f << "div { background-image: url(#{local_image_path}); }"
    }
    # Default: rebase to current dir
    assert_equal(
      'div{background-image:url(images/lenna.jpg)}',
      compress("@import url(#{local_import_path});")
    )
    # No rebase
    assert_equal(
      'div{background-image:url(../images/lenna.jpg)}',
      compress("@import url(#{local_import_path});", rebase_urls: false)
    )
    # Rebase to different dir
    assert_equal(
      'div{background-image:url(lenna.jpg)}',
      compress("@import url(#{local_import_path});", rebase_to: 'images')
    )
  ensure
    File.unlink(local_import_path)  if File.exist?(local_import_path)
  end


  # These are only superficial checks to see if the clean-css options are set.
  # We check a few distinctive options for each mode. See clean-css/lib/options/compatibility.js
  # Note that the earlier IE modes include the later modes, but the reverse isn't true.
  def test_compatibility
    klass = Class.new(RubyCleanCSS::Compressor) do
      public :native_options
    end
    ie8_changed_props = {'backgroundClipMerging'   => false,
                         'backgroundOriginMerging' => false,
                         'backgroundSizeMerging'   => false,
                         'iePrefixHack'            => true,
                         'merging'                 => false}.freeze
    ie9_changed_props = {'ieFilters'    => true,
                         'ieSuffixHack' => true}.freeze

    klass.new(compatibility: 'ie7').tap do |c|
      assert_equal(true, c.native_options['compatibility']['selectors']['ie7Hack'])
    end

    klass.new(compatibility: 'ie8').tap do |c|
      # ie8 shouldn't include ie7
      assert_not_equal(true, c.native_options['compatibility']['selectors']['ie7Hack'])

      assert_equal(false, c.native_options['compatibility']['colors']['opacity'])

      ie8_changed_props.each do |name, val|
        assert_equal(val, c.native_options['compatibility']['properties'][name])
      end
    end

    klass.new(compatibility: 'ie9').tap do |c|
      # ie9 shouldn't include ie8
      ie8_changed_props.each do |name, val|
        assert_not_equal(val, c.native_options['compatibility']['properties'][name])
      end

      ie9_changed_props.each do |name, val|
        assert_equal(val, c.native_options['compatibility']['properties'][name])
      end
    end

    klass.new(compatibility: '*').tap do |c|
      # ie10+ shouldn't include ie9
      ie9_changed_props.each do |name, val|
        assert_not_equal(val, c.native_options['compatibility']['properties'][name])
      end

      assert_equal(false, c.native_options['compatibility']['properties']['ieSuffixHack'])

      # Should match the default
      klass.new.tap do |c_default|
        assert_equal(c_default.native_options['compatibility'],
                     c.native_options['compatibility'])
      end
    end
  end


  def compress(str, options = {})
    c = RubyCleanCSS::Compressor.new(options)
    c.compress(str)
    if c.last_result[:errors].any?
      STDERR.puts("clean-css errors: " + c.last_result[:errors].join("\n"))
    end
    if c.last_result[:warnings].any?
      STDERR.puts("clean-css warnings: " + c.last_result[:warnings].join("\n"))
    end
    c.last_result[:min]
  end

end
