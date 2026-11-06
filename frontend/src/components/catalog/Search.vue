<template>

</template>

<script lang="ts">
import { defineComponent } from "vue";

const DEBOUNCE_MS = 1000;

function debounce<T extends (...args: any[]) => void>(fn: T, ms: number): T {
  let timeoutId: ReturnType<typeof setTimeout> | null = null;
  return ((...args: any[]) => {
    if (timeoutId) clearTimeout(timeoutId);
    timeoutId = setTimeout(() => fn(...args), ms);
  }) as T;
}

export default defineComponent({
  name: "Search",
  data() {
    return {
      search_debouncer: debounce((q: string) => this.$emit("search", q.trim()), DEBOUNCE_MS),
    }
  },
  props: {
    query: {
      type: String,
      default: ""
    }
  },
  emits: [ "search" ]
});
</script>
