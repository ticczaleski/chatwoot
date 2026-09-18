<script setup>
import { computed } from 'vue';

import MessageMeta from '../MessageMeta.vue';
import CaptainGenerationDetails from '../CaptainGenerationDetails.vue';

import { emitter } from 'shared/helpers/mitt';
import { useMessageContext } from '../provider.js';
import { useI18n } from 'vue-i18n';

import MessageFormatter from 'shared/helpers/MessageFormatter.js';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { MESSAGE_VARIANTS, ORIENTATION, SENDER_TYPES } from '../constants';

const props = defineProps({
  hideMeta: { type: Boolean, default: false },
});

const {
  variant,
  orientation,
  inReplyTo,
  shouldGroupWithNext,
  id,
  sender,
  senderType,
} = useMessageContext();
const { t } = useI18n();

const isCaptainMessage = computed(
  () =>
    (sender.value?.type ?? senderType.value) === SENDER_TYPES.CAPTAIN_ASSISTANT
);

const metaColorClass = computed(() =>
  variant.value === MESSAGE_VARIANTS.PRIVATE
    ? 'text-amber-800/80 dark:text-amber-200/80'
    : 'text-wa-text-muted dark:text-wa-text-muted-dark'
);

const emailMetaClass = computed(() =>
  variant.value === MESSAGE_VARIANTS.EMAIL ? 'px-3 pb-3' : ''
);

const varaintBaseMap = {
  [MESSAGE_VARIANTS.AGENT]:
    'bg-wa-bubble-out dark:bg-wa-bubble-out-dark text-wa-text dark:text-wa-text-dark shadow-[0_1px_0.5px_rgba(11,20,26,0.13)]',
  [MESSAGE_VARIANTS.PRIVATE]:
    'bg-wa-bubble-private dark:bg-amber-950 text-wa-bubble-private-text dark:text-amber-200 border border-amber-300 dark:border-amber-800 shadow-[0_1px_0.5px_rgba(11,20,26,0.13)] [&_.prosemirror-mention-node]:font-semibold',
  [MESSAGE_VARIANTS.USER]:
    'bg-wa-bubble-in dark:bg-wa-bubble-in-dark text-wa-text dark:text-wa-text-dark shadow-[0_1px_0.5px_rgba(11,20,26,0.13)]',
  [MESSAGE_VARIANTS.ACTIVITY]:
    'bg-white dark:bg-wa-panel-dark text-wa-text-muted dark:text-wa-text-muted-dark text-xs shadow-sm uppercase tracking-wider px-3 py-1.5 rounded-lg border border-wa-border/50 dark:border-wa-border-dark/50',
  [MESSAGE_VARIANTS.BOT]:
    'bg-wa-bubble-out dark:bg-wa-bubble-out-dark text-wa-text dark:text-wa-text-dark shadow-[0_1px_0.5px_rgba(11,20,26,0.13)]',
  [MESSAGE_VARIANTS.TEMPLATE]:
    'bg-wa-bubble-out dark:bg-wa-bubble-out-dark text-wa-text dark:text-wa-text-dark shadow-[0_1px_0.5px_rgba(11,20,26,0.13)]',
  [MESSAGE_VARIANTS.ERROR]: 'bg-n-ruby-4 text-n-ruby-12',
  [MESSAGE_VARIANTS.EMAIL]: 'w-full',
  [MESSAGE_VARIANTS.UNSUPPORTED]:
    'bg-wa-bubble-private dark:bg-amber-950 border border-dashed border-amber-500 text-wa-bubble-private-text',
};

const orientationMap = {
  [ORIENTATION.LEFT]:
    'left-bubble rounded-lg ltr:rounded-tl-none rtl:rounded-tr-none',
  [ORIENTATION.RIGHT]:
    'right-bubble rounded-lg ltr:rounded-tr-none rtl:rounded-tl-none',
  [ORIENTATION.CENTER]: 'rounded-md',
};

const flexOrientationClass = computed(() => {
  const map = {
    [ORIENTATION.LEFT]: 'justify-start',
    [ORIENTATION.RIGHT]: 'justify-end',
    [ORIENTATION.CENTER]: 'justify-center',
  };

  return map[orientation.value];
});

const messageClass = computed(() => {
  const classToApply = [varaintBaseMap[variant.value]];

  if (variant.value !== MESSAGE_VARIANTS.ACTIVITY) {
    classToApply.push(orientationMap[orientation.value]);
  } else {
    classToApply.push('rounded-lg');
  }

  return classToApply;
});

const scrollToMessage = () => {
  emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, {
    messageId: inReplyTo.value.id,
  });
};

const shouldShowMeta = computed(
  () =>
    !props.hideMeta &&
    !shouldGroupWithNext.value &&
    variant.value !== MESSAGE_VARIANTS.ACTIVITY
);

const replyToPreview = computed(() => {
  if (!inReplyTo) return '';

  const { content, attachments } = inReplyTo.value;

  if (content) return new MessageFormatter(content).formattedMessage;
  if (attachments?.length) {
    const firstAttachment = attachments[0];
    const fileType = firstAttachment.fileType ?? firstAttachment.file_type;

    return t(`CHAT_LIST.ATTACHMENTS.${fileType}.CONTENT`);
  }

  return t('CONVERSATION.REPLY_MESSAGE_NOT_FOUND');
});
</script>

<template>
  <div
    class="text-[14.2px] leading-[19px] min-w-0"
    :class="[
      messageClass,
      {
        'max-w-[75%] sm:max-w-[65%]': variant !== MESSAGE_VARIANTS.EMAIL,
      },
    ]"
  >
    <div
      v-if="inReplyTo"
      class="p-2 -mx-1 mb-2 rounded-md cursor-pointer bg-black/5 dark:bg-white/5 border-l-4 border-wa-teal"
      @click="scrollToMessage"
    >
      <div
        v-dompurify-html="replyToPreview"
        class="prose prose-bubble line-clamp-2"
      />
    </div>
    <slot />
    <template v-if="shouldShowMeta">
      <CaptainGenerationDetails
        v-if="isCaptainMessage"
        :message-id="id"
        class="mt-2"
      >
        <template #meta>
          <MessageMeta :class="[emailMetaClass, metaColorClass]" />
        </template>
      </CaptainGenerationDetails>
      <MessageMeta
        v-else
        :class="[emailMetaClass, metaColorClass]"
        class="mt-1 text-[11px] justify-end"
      />
    </template>
  </div>
</template>
