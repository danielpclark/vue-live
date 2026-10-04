<template><span class="setup">{{ doubled }}</span></template>
<script setup>
import { ref, computed } from 'vue'
const n = ref(21)
const doubled = computed(() => n.value * 2)
</script>
<style scoped lang="scss">
$c: rgb(0, 0, 255);
.setup { color: $c; }
</style>
