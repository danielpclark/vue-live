# frozen_string_literal: true

require_relative 'test_helper'

class ParserTest < Minitest::Test
  def parse(src)
    VueLive::SFC::Parser.parse(src, filename: 'T.vue')
  end

  def test_extracts_blocks_and_attributes
    d = parse(<<~V)
      <template lang="html">
        <div><template v-if="a"><i/></template><template #s="{ x }">{{ x }}</template></div>
      </template>
      <script setup lang="ts">const a = 1</script>
      <style scoped>.a{}</style>
      <style lang='scss' module="classes">.b{}</style>
      <docs>hello</docs>
    V
    assert_includes d.template.content, '<template #s="{ x }">{{ x }}</template></div>'
    assert_equal 'html', d.template.lang
    assert d.script_setup.setup?
    assert_equal 'ts', d.script_setup.lang
    assert_nil d.script
    assert_equal 2, d.styles.size
    assert d.styles[0].scoped?
    assert_equal 'scss', d.styles[1].lang
    assert_equal 'classes', d.styles[1].attrs['module']
    assert_equal %w[docs], d.custom_blocks.map(&:type)
    assert_equal ['<script setup>', '<script lang="ts">', '<style lang="scss">', '<style module>'], d.advanced_features
  end

  def test_plain_component_has_no_advanced_features
    d = parse("<template><p/></template><script>export default {}</script><style scoped>p{}</style>")
    assert_empty d.advanced_features
    assert d.scoped_styles?
  end

  def test_both_script_kinds
    d = parse("<script>export default {}</script><script setup>const x = 1</script>")
    refute_nil d.script
    refute_nil d.script_setup
  end

  def test_nested_templates_are_balanced
    d = parse("<template><template v-for=\"i in 3\"><template v-if=\"i\">x</template></template></template>")
    assert_equal '<template v-for="i in 3"><template v-if="i">x</template></template>', d.template.content
  end

  def test_src_attribute
    d = parse('<template src="./a.html"/><script src="./a.js"></script>')
    assert_equal './a.html', d.template.src
    assert_equal './a.js', d.script.src
  end

  def test_script_content_with_angle_brackets
    d = parse("<template><p/></template><script>const f = (a, b) => a < b && b > a; export default { f }</script>")
    assert_includes d.script.content, 'a < b && b > a'
  end

  def test_unterminated_block
    e = assert_raises(VueLive::CompileError) { parse("<template><p>oops") }
    assert_match(/unterminated <template>/, e.message)
    assert_match(/T\.vue/, e.message)
  end

  def test_requires_template_or_script
    assert_raises(VueLive::CompileError) { parse("<style>.a{}</style>") }
  end

  def test_duplicate_template
    assert_raises(VueLive::CompileError) { parse("<template><a/></template><template><b/></template>") }
  end
end
