import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { computed } from 'vue';
import MessagesView from '../MessagesView.vue';
import MessageList from 'next/message/MessageList.vue';

vi.mock('dashboard/composables/useLabelSuggestions', () => ({
  useLabelSuggestions: () => ({
    captainTasksEnabled: computed(() => false),
    isLabelSuggestionFeatureEnabled: computed(() => false),
    getLabelSuggestions: vi.fn().mockResolvedValue([]),
  }),
}));

vi.mock('dashboard/composables/useContactConversationNavigation', () => ({
  useContactConversationNavigation: () => ({
    olderConversation: computed(() => null),
    newerConversation: computed(() => null),
    buildConversationPath: vi.fn(),
  }),
}));

const CHAT = {
  id: 1,
  inbox_id: 1,
  can_reply: true,
  status: 'open',
  unread_count: 0,
  agent_last_seen_at: 0,
  messages: [],
  meta: { sender: { id: 2 } },
};

const buildStore = ({ chat = {}, inbox = {} } = {}) =>
  createStore({
    getters: {
      getSelectedChat: () => ({ ...CHAT, ...chat }),
      getCurrentUserID: () => 7,
      getAllMessagesLoaded: () => false,
      getCurrentAccountId: () => 1,
      'globalConfig/isMetaMessageSendingDisabled': () => false,
      'inboxes/getInbox': () => () => ({
        id: 1,
        channel_type: 'Channel::Api',
        ...inbox,
      }),
      'inboxes/getInstagramInboxByInstagramId': () => () => null,
      'conversationTypingStatus/getUserList': () => () => [],
    },
    actions: {
      fetchAllAttachments: vi.fn(),
      fetchPreviousMessages: vi.fn(),
      sendMessageWithData: vi.fn(),
      markMessagesRead: vi.fn(),
    },
  });

const mountWith = (options = {}) => {
  const store = buildStore(options);
  return shallowMount(MessagesView, {
    global: {
      plugins: [store],
      mocks: { $t: key => key },
    },
  });
};

describe('MessagesView wallpaper', () => {
  it('applies the transparent doodle background with separate light/dark base colors', () => {
    const wrapper = mountWith();
    const wallpaper = wrapper.find('[data-testid="conversation-wallpaper"]');

    expect(wallpaper.exists()).toBe(true);
    expect(wallpaper.classes()).toEqual(
      expect.arrayContaining([
        'bg-wa-bg',
        'dark:bg-wa-chat-bg-dark',
        'before:bg-wa-doodle',
        'dark:before:bg-wa-doodle-dark',
      ])
    );
  });

  it('does not apply runtime opacity or inversion to the wallpaper layer', () => {
    const wrapper = mountWith();
    const wallpaperClass = wrapper
      .find('[data-testid="conversation-wallpaper"]')
      .attributes('class');

    expect(wallpaperClass).not.toMatch(/before:opacity/);
    expect(wallpaperClass).not.toMatch(/before:invert/);
    expect(wallpaperClass).not.toMatch(/filter-none/);
  });

  it('keeps the wallpaper stationary while the message list scrolls inside it', () => {
    const wrapper = mountWith();
    const wallpaper = wrapper.find('[data-testid="conversation-wallpaper"]');

    expect(wallpaper.classes()).toEqual(
      expect.arrayContaining(['relative', 'overflow-hidden'])
    );

    const messageList = wrapper.findComponent(MessageList);
    expect(messageList.classes()).toEqual(
      expect.arrayContaining(['absolute', 'inset-0', 'overflow-y-auto'])
    );
  });
});
