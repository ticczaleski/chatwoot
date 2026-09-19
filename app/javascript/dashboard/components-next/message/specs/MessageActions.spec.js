import { mount } from '@vue/test-utils';
import MessageActions from '../MessageActions.vue';

const mountActions = () =>
  mount(MessageActions, {
    global: {
      stubs: {
        // Render the trigger and content slots inline so we can interact with the
        // real emoji buttons without depending on Popover's teleport/positioning.
        Popover: {
          template:
            '<div><slot :is-open="true" /><slot name="content" :hide="hide" /></div>',
          methods: { hide() {} },
          expose: ['show', 'hide'],
        },
      },
    },
  });

describe('MessageActions', () => {
  it('renders exactly six quick reaction emojis', () => {
    const wrapper = mountActions();
    const emojiButtons = wrapper.findAll('[role="menuitem"]');
    expect(emojiButtons).toHaveLength(6);
  });

  it('emits toggle with the picked emoji', async () => {
    const wrapper = mountActions();
    const firstEmojiButton = wrapper.find('[role="menuitem"]');

    await firstEmojiButton.trigger('click');

    expect(wrapper.emitted('toggle')).toHaveLength(1);
    expect(typeof wrapper.emitted('toggle')[0][0]).toBe('string');
    expect(wrapper.emitted('toggle')[0][0]).not.toBe('');
  });

  it('the trigger button is keyboard-focusable and carries an accessible label', () => {
    const wrapper = mountActions();
    const trigger = wrapper.find('button');

    expect(trigger.exists()).toBe(true);
    expect(trigger.attributes('aria-label')).toBeTruthy();
  });

  it('quick emoji buttons are inside a menu with the expected roles', () => {
    const wrapper = mountActions();
    expect(wrapper.find('[role="menu"]').exists()).toBe(true);
    wrapper.findAll('[role="menuitem"]').forEach(button => {
      expect(button.element.tagName).toBe('BUTTON');
    });
  });
});
