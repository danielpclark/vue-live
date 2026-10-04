# frozen_string_literal: true

require_relative 'test_helper'

class SourceMapTest < Minitest::Test
  def test_vlq
    assert_equal 'A', VueLive::SourceMap.vlq(0)
    assert_equal 'C', VueLive::SourceMap.vlq(1)
    assert_equal 'D', VueLive::SourceMap.vlq(-1)
    assert_equal 'I', VueLive::SourceMap.vlq(4)
    assert_equal '2H', VueLive::SourceMap.vlq(123)
    assert_equal 'ggC', VueLive::SourceMap.vlq(1024)
  end

  def test_mappings_and_json
    map = VueLive::SourceMap.new('A.vue', "a\nb\nc")
    map.add_block(generated_line: 2, original_line: 10, count: 2)
    h = map.to_h
    assert_equal 3, h['version']
    assert_equal ['A.vue'], h['sources']
    assert_equal ["a\nb\nc"], h['sourcesContent']
    assert_equal ';AASA;AACA', h['mappings'] # line 1 empty, line 2 -> src 10, line 3 -> src 11
    assert_match(%r{\A//# sourceMappingURL=data:application/json;charset=utf-8;base64,}, map.inline_comment)
    assert_equal h, JSON.parse(Base64.decode64(map.inline_comment.split('base64,').last))
  end

  def test_empty
    assert VueLive::SourceMap.new('A.vue', '').empty?
  end
end
