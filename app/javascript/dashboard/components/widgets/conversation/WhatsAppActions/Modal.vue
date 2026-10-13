<script>
export default {
  props: {
    show: {
      type: Boolean,
      default: false,
    },
    conversation: {
      type: Object,
      default: () => ({}),
    },
  },
  emits: ['close', 'cancel', 'update:show'],
  computed: {
    localShow: {
      get() {
        return this.show;
      },
      set(value) {
        this.$emit('update:show', value);
      },
    },
    contactName() {
      return (
        this.conversation?.meta?.sender?.name ||
        this.conversation?.meta?.sender?.phone_number ||
        'Contato'
      );
    },
    contactPhoneNumber() {
      return this.conversation?.meta?.sender?.phone_number || '';
    },
    cleanPhoneNumber() {
      return this.contactPhoneNumber.replace(/\D/g, '');
    },
    inboxId() {
      return this.conversation?.inbox_id || 1;
    },
    instance() {
      // Inbox 2 é o canal Suporte TI, Inbox 1 é TI 1
      return this.inboxId === 2 ? 'suporte' : 'ti1';
    },
    modalHeaderTitle() {
      return 'Recursos e Ações do WhatsApp';
    },
    modalHeaderSubtitle() {
      const phoneDisplay = this.contactPhoneNumber
        ? ` (${this.contactPhoneNumber})`
        : '';
      return `Envie enquetes, menus de lista, botões interativos, localização e Pix para ${this.contactName}${phoneDisplay}`;
    },
    iframeUrl() {
      const base = 'https://whatsapi-ti1.zaleski.pro/chatwoot-app/index.html';
      const params = new URLSearchParams({
        phone: this.cleanPhoneNumber,
        name: this.contactName,
        conversation_id: this.conversation?.id || '',
        inbox_id: this.inboxId,
        instance: this.instance,
      });
      return `${base}?${params.toString()}`;
    },
  },
  mounted() {
    window.addEventListener('message', this.handleIframeMessage);
  },
  beforeUnmount() {
    window.removeEventListener('message', this.handleIframeMessage);
  },
  methods: {
    onClose() {
      this.$emit('close');
      this.$emit('cancel');
    },
    sendAppContextToIframe() {
      const iframe = this.$refs.actionsIframe;
      if (!iframe || !iframe.contentWindow) return;

      const payload = {
        event: 'appContext',
        data: {
          contact: {
            name: this.contactName,
            phone_number: this.contactPhoneNumber,
          },
          conversation: {
            id: this.conversation?.id,
            inbox_id: this.inboxId,
          },
          instance: this.instance,
        },
      };

      try {
        iframe.contentWindow.postMessage(payload, '*');
      } catch (err) {
        // Silently ignore cross-origin postMessage errors
      }
    },
    onIframeLoad() {
      this.sendAppContextToIframe();
    },
    handleIframeMessage(event) {
      if (!event.data) return;
      try {
        const data =
          typeof event.data === 'string' ? JSON.parse(event.data) : event.data;

        if (data === 'chatwoot-dashboard-app:fetch-info') {
          this.sendAppContextToIframe();
        } else if (data.event === 'closeModal') {
          this.onClose();
        }
      } catch (e) {
        if (event.data === 'chatwoot-dashboard-app:fetch-info') {
          this.sendAppContextToIframe();
        }
      }
    },
  },
};
</script>

<template>
  <woot-modal
    v-model:show="localShow"
    :on-close="onClose"
    size="modal-big"
  >
    <woot-modal-header
      :header-title="modalHeaderTitle"
      :header-content="modalHeaderSubtitle"
    />
    <div class="whatsapp-actions-modal-wrapper">
      <iframe
        ref="actionsIframe"
        :src="iframeUrl"
        class="whatsapp-actions-iframe"
        allow="clipboard-write"
        @load="onIframeLoad"
      />
    </div>
  </woot-modal>
</template>

<style scoped>
.whatsapp-actions-modal-wrapper {
  width: 100%;
  height: 640px;
  max-height: 80vh;
  padding: 0;
  margin: 0;
  overflow: hidden;
  background-color: #111b21;
  border-radius: 0 0 12px 12px;
}

.whatsapp-actions-iframe {
  width: 100%;
  height: 100%;
  border: none;
  display: block;
}
</style>
