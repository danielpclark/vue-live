<template>
  <section class="hello">
    <h2>{{ greeting }}, {{ name }}!</h2>
    <p>
      This component was compiled by <code>vue_live</code> straight from
      <code>app/vue/HelloVueLive.vue</code> — no build step.
    </p>
    <button type="button" @click="count++">Clicked {{ count }} time{{ count === 1 ? '' : 's' }}</button>
  </section>
</template>

<script>
export default {
  props: {
    name: { type: String, default: 'world' }
  },
  data() {
    return { count: 0 }
  },
  computed: {
    greeting() {
      return this.count > 4 ? 'Still hello' : 'Hello'
    }
  }
}
</script>

<style scoped>
.hello {
  font-family: system-ui, sans-serif;
  padding: 1rem 1.5rem;
  border: 1px solid #42b883;
  border-radius: 8px;
  max-width: 32rem;
}
.hello h2 {
  color: #42b883;
  margin-top: 0;
}
button {
  background: #35495e;
  color: white;
  border: 0;
  border-radius: 4px;
  padding: 0.5rem 1rem;
  cursor: pointer;
}
</style>
