<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  count: { type: Number, required: true },
  alignBottom: { type: Boolean, default: false },
});

const { t } = useI18n();

const displayCount = computed(() =>
  props.count > 9 ? t('CHAT_LIST.UNREAD_COUNT_OVERFLOW') : props.count
);
</script>

<template>
  <span
    v-if="count > 0"
    class="bg-wa-green rounded-full h-5 min-w-5 px-1.5 w-fit font-bold text-xs leading-4 text-white inline-grid place-items-center flex-shrink-0"
    :class="{
      'mb-0.5': alignBottom,
    }"
  >
    {{ displayCount }}
  </span>
  <span v-else />
</template>
