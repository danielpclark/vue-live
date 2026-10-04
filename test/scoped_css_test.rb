# frozen_string_literal: true

require_relative 'test_helper'

class ScopedCSSTest < Minitest::Test
  def rw(css)
    VueLive::ScopedCSS.rewrite(css, 'data-v-abc').strip
  end

  def test_simple_selectors
    assert_equal '.a[data-v-abc] { color: red }', rw('.a { color: red }')
    assert_equal 'div[data-v-abc] p[data-v-abc] {}', rw('div[data-v-abc] p {}').sub('[data-v-abc][data-v-abc]', '[data-v-abc]')
    assert_equal '.a .b[data-v-abc], .c > .d[data-v-abc] { x: y }', rw('.a .b, .c > .d { x: y }')
  end

  def test_pseudo_elements_stay_last
    assert_equal '.a[data-v-abc]::before { x: y }', rw('.a::before { x: y }')
    assert_equal '.a[data-v-abc]:after { x: y }', rw('.a:after { x: y }')
    assert_equal '*[data-v-abc]::placeholder { x: y }', rw('::placeholder { x: y }')
  end

  def test_pseudo_classes
    assert_equal '.a:hover[data-v-abc] { x: y }', rw('.a:hover { x: y }')
    assert_equal '.x:not(.y, .z)[data-v-abc] { }', rw('.x:not(.y, .z) { }')
  end

  def test_deep
    assert_equal '.a[data-v-abc] .b { x: y }', rw('.a :deep(.b) { x: y }')
    assert_equal '.a[data-v-abc] .b { x: y }', rw('.a ::v-deep .b { x: y }')
    assert_equal '.a[data-v-abc] .b { x: y }', rw('.a >>> .b { x: y }')
    assert_equal '.a[data-v-abc] .b .c { x: y }', rw('.a ::v-deep(.b) .c { x: y }')
  end

  def test_slotted_and_global
    assert_equal '.s[data-v-abc-s] { x: y }', rw(':slotted(.s) { x: y }')
    assert_equal '.g { x: y }', rw(':global(.g) { x: y }')
  end

  def test_at_rules
    out = rw(<<~CSS)
      @import url("x.css");
      @media (min-width: 1px) { .m, h1 { x: y } }
      @supports (display: grid) { .g { x: y } }
      @keyframes spin { from { x: 1 } to { x: 2 } }
      @font-face { font-family: F; src: url(f.woff) }
    CSS
    assert_includes out, '@import url("x.css");'
    assert_includes out, '@media (min-width: 1px) { .m[data-v-abc], h1[data-v-abc] { x: y } }'
    assert_includes out, '@supports (display: grid) { .g[data-v-abc] { x: y } }'
    assert_includes out, '@keyframes spin { from { x: 1 } to { x: 2 } }'
    assert_includes out, '@font-face { font-family: F; src: url(f.woff) }'
  end

  def test_comments_and_strings
    assert_equal '.a[data-v-abc] { content: "{,}" }', rw('/* .b { } */ .a { content: "{,}" }')
    assert_equal 'a[href="x,y"][data-v-abc] { x: y }', rw('a[href="x,y"] { x: y }')
  end
end
