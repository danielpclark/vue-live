<template>
  <div id="root" class="app">
    <h1>{{ title }}</h1>
    <Child :n="count" @bump="count++" />
    <template v-if="count > 2"><p class="many">many</p></template>
  </div>
</template>

<script>
import Child from './nested/Child.vue'
import { shout } from './shared/util.js'

export default {
  components: { Child },
  props: { title: { type: String, default: 'vue_live' } },
  data() { return { count: 0 } },
  computed: { loud() { return shout(this.title) } }
}
</script>

<style scoped>
.app { padding: 4px; }
h1 { color: rgb(66, 184, 131); }
</style>
