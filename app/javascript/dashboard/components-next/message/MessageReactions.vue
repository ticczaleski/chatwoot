<script setup>
import { useI18n } from 'vue-i18n';

defineProps({
  reactions: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['toggle']);
const { t } = useI18n();

// Clicking your own pill removes it (empty emoji); clicking any other pill moves your
// reaction to that emoji. The backend always replaces the caller's own reaction with
// whatever is sent, so there is no separate "replace" call to make here.
function handlePillClick(reaction) {
  emit('toggle', reaction.reactedByCurrentUser ? '' : reaction.emoji);
}

function pillLabel(reaction) {
  return reaction.reactedByCurrentUser
    ? t('CONVERSATION.REACTIONS.REMOVE')
    : t('CONVERSATION.REACTIONS.REACTED_WITH', { emoji: reaction.emoji });
}
</script>

<template>
  <div
    v-if="reactions.length"
    class="flex flex-wrap gap-1 mt-1"
    data-testid="message-reactions"
  >
    <button
      v-for="reaction in reactions"
      :key="reaction.emoji"
      type="button"
      class="flex items-center gap-1 h-6 px-2 rounded-full text-xs border transition-colors"
      :class="[
        reaction.reactedByCurrentUser
          ? 'bg-n-brand/10 border-n-brand/40 text-n-brand'
          : 'bg-n-alpha-1 border-n-weak text-n-slate-11 hover:bg-n-alpha-2',
      ]"
      :aria-pressed="reaction.reactedByCurrentUser"
      :aria-label="pillLabel(reaction)"
      @click="handlePillClick(reaction)"
    >
      <span aria-hidden="true">{{ reaction.emoji }}</span>
      <span>{{ reaction.count }}</span>
    </button>
  </div>
</template>
