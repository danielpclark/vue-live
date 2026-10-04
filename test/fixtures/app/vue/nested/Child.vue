<template>
  <button class="child" @click="$emit('bump')">n = {{ n }}</button>
</template>
<script>
export default { props: { n: Number }, emits: ['bump'] }
</script>
<style scoped>
.child { color: rgb(255, 0, 0); }
</style>
<style>
body { margin: 0; }
</style>
