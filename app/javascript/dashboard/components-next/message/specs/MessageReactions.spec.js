import { mount } from '@vue/test-utils';
import MessageReactions from '../MessageReactions.vue';

const REACTIONS = [
  { emoji: '👍', count: 2, reactedByCurrentUser: true },
  { emoji: '😀', count: 1, reactedByCurrentUser: false },
];

describe('MessageReactions', () => {
  it('renders nothing when there are no reactions', () => {
    const wrapper = mount(MessageReactions, { props: { reactions: [] } });
    expect(wrapper.find('[data-testid="message-reactions"]').exists()).toBe(
      false
    );
  });

  it('renders one pill per aggregated reaction with its emoji and count', () => {
    const wrapper = mount(MessageReactions, {
      props: { reactions: REACTIONS },
    });
    const pills = wrapper.findAll('button');

    expect(pills).toHaveLength(2);
    expect(pills[0].text()).toContain('👍');
    expect(pills[0].text()).toContain('2');
    expect(pills[1].text()).toContain('😀');
    expect(pills[1].text()).toContain('1');
  });

  it('marks the pill the current user reacted with via aria-pressed', () => {
    const wrapper = mount(MessageReactions, {
      props: { reactions: REACTIONS },
    });
    const pills = wrapper.findAll('button');

    expect(pills[0].attributes('aria-pressed')).toBe('true');
    expect(pills[1].attributes('aria-pressed')).toBe('false');
  });

  it('emits an empty emoji to remove the reaction when clicking your own pill', async () => {
    const wrapper = mount(MessageReactions, {
      props: { reactions: REACTIONS },
    });
    await wrapper.findAll('button')[0].trigger('click');

    expect(wrapper.emitted('toggle')).toEqual([['']]);
  });

  it('emits the target emoji when clicking a pill you have not reacted to', async () => {
    const wrapper = mount(MessageReactions, {
      props: { reactions: REACTIONS },
    });
    await wrapper.findAll('button')[1].trigger('click');

    expect(wrapper.emitted('toggle')).toEqual([['😀']]);
  });

  it('pills are keyboard operable (native buttons receive focus and Enter/Space activation)', () => {
    const wrapper = mount(MessageReactions, {
      props: { reactions: REACTIONS },
    });
    wrapper.findAll('button').forEach(pill => {
      expect(pill.element.tagName).toBe('BUTTON');
      expect(pill.attributes('type')).toBe('button');
    });
  });
});
