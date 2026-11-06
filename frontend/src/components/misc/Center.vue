<template>
  <div class="d-flex justify-content-center align-items-center">
    <slot></slot>
  </div>
</template>

<script lang="ts">
import { defineComponent } from 'vue'

export default defineComponent({
  name: 'Center'
})
</script>
