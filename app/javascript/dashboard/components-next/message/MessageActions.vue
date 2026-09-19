<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const emit = defineEmits(['toggle']);
// WhatsApp's own default quick-reaction set — recognizable, no picker-within-picker needed.
const QUICK_EMOJIS = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
const LONG_PRESS_MS = 500;

const { t } = useI18n();

const popoverRef = ref(null);
let longPressTimer = null;

function pick(emoji, hide) {
  emit('toggle', emoji);
  hide();
}

function startLongPress() {
  clearTimeout(longPressTimer);
  longPressTimer = setTimeout(() => {
    popoverRef.value?.show();
  }, LONG_PRESS_MS);
}

function cancelLongPress() {
  clearTimeout(longPressTimer);
}
</script>

<template>
  <Popover
    ref="popoverRef"
    align="start"
    class="opacity-0 group-hover:opacity-100 group-focus-within:opacity-100 focus-within:opacity-100"
  >
    <template #default>
      <NextButton
        ghost
        slate
        sm
        icon="i-lucide-smile-plus"
        :title="t('CONVERSATION.CONTEXT_MENU.REACT')"
        :aria-label="t('CONVERSATION.CONTEXT_MENU.REACT')"
        @pointerdown="startLongPress"
        @pointerup="cancelLongPress"
        @pointerleave="cancelLongPress"
      />
    </template>
    <template #content="{ hide }">
      <div class="flex items-center gap-1 p-1.5" role="menu">
        <button
          v-for="emoji in QUICK_EMOJIS"
          :key="emoji"
          type="button"
          role="menuitem"
          class="flex items-center justify-center w-8 h-8 rounded-full text-lg hover:bg-n-alpha-2 transition-transform hover:scale-110"
          :aria-label="t('CONVERSATION.REACTIONS.REACTED_WITH', { emoji })"
          @click="pick(emoji, hide)"
        >
          {{ emoji }}
        </button>
      </div>
    </template>
  </Popover>
</template>
