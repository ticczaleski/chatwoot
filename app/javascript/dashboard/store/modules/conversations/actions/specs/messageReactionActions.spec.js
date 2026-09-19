import messageReactionActions, {
  applyOptimisticReaction,
} from '../messageReactionActions';
import MessageApi from '../../../../../api/inbox/message';
import types from '../../../../mutation-types';

vi.mock('../../../../../api/inbox/message');

describe('applyOptimisticReaction', () => {
  it('adds a new pill when the user has not reacted yet', () => {
    const result = applyOptimisticReaction([], '👍');
    expect(result).toEqual([
      { emoji: '👍', count: 1, reacted_by_current_user: true },
    ]);
  });

  it('increments an existing pill the user has not reacted to yet', () => {
    const result = applyOptimisticReaction(
      [{ emoji: '👍', count: 2, reacted_by_current_user: false }],
      '👍'
    );
    expect(result).toEqual([
      { emoji: '👍', count: 3, reacted_by_current_user: true },
    ]);
  });

  it('moves the user from their current pill to a new one, dropping the old pill at zero', () => {
    const result = applyOptimisticReaction(
      [{ emoji: '👍', count: 1, reacted_by_current_user: true }],
      '😀'
    );
    expect(result).toEqual([
      { emoji: '😀', count: 1, reacted_by_current_user: true },
    ]);
  });

  it('keeps the old pill when others still hold it after the user moves away', () => {
    const result = applyOptimisticReaction(
      [{ emoji: '👍', count: 2, reacted_by_current_user: true }],
      '😀'
    );
    expect(result).toEqual([
      { emoji: '👍', count: 1, reacted_by_current_user: false },
      { emoji: '😀', count: 1, reacted_by_current_user: true },
    ]);
  });

  it('removes the pill entirely with an empty emoji', () => {
    const result = applyOptimisticReaction(
      [{ emoji: '👍', count: 1, reacted_by_current_user: true }],
      ''
    );
    expect(result).toEqual([]);
  });

  it('is a no-op when removing and the user had not reacted', () => {
    const result = applyOptimisticReaction(
      [{ emoji: '👍', count: 1, reacted_by_current_user: false }],
      ''
    );
    expect(result).toEqual([
      { emoji: '👍', count: 1, reacted_by_current_user: false },
    ]);
  });
});

describe('messageReactionActions', () => {
  const conversationId = 1;
  const messageId = 42;

  const buildContext = (message = { id: messageId, reactions: [] }) => {
    const commit = vi.fn();
    const getters = {
      getConversationById: vi.fn().mockReturnValue({ messages: [message] }),
    };
    return { commit, getters, rootGetters: { getCurrentUser: { id: 7 } } };
  };

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('#toggleMessageReaction', () => {
    it('commits an optimistic update immediately, then the server result', async () => {
      const context = buildContext();
      MessageApi.toggleReaction.mockResolvedValue({
        data: {
          reactions: [{ emoji: '👍', count: 1, reacted_by_current_user: true }],
        },
      });

      await messageReactionActions.toggleMessageReaction(context, {
        conversationId,
        messageId,
        emoji: '👍',
      });

      expect(context.commit).toHaveBeenNthCalledWith(
        1,
        types.UPDATE_MESSAGE_REACTIONS,
        {
          conversationId,
          messageId,
          reactions: [{ emoji: '👍', count: 1, reacted_by_current_user: true }],
        }
      );
      expect(context.commit).toHaveBeenNthCalledWith(
        2,
        types.UPDATE_MESSAGE_REACTIONS,
        {
          conversationId,
          messageId,
          reactions: [{ emoji: '👍', count: 1, reacted_by_current_user: true }],
        }
      );
      expect(MessageApi.toggleReaction).toHaveBeenCalledWith(
        conversationId,
        messageId,
        '👍'
      );
    });

    it('rolls back to the previous reactions and re-throws when the request fails', async () => {
      const existingMessage = {
        id: messageId,
        reactions: [{ emoji: '😀', count: 1, reacted_by_current_user: false }],
      };
      const context = buildContext(existingMessage);
      MessageApi.toggleReaction.mockRejectedValue(new Error('network blip'));

      await expect(
        messageReactionActions.toggleMessageReaction(context, {
          conversationId,
          messageId,
          emoji: '👍',
        })
      ).rejects.toThrow('network blip');

      expect(context.commit).toHaveBeenLastCalledWith(
        types.UPDATE_MESSAGE_REACTIONS,
        {
          conversationId,
          messageId,
          reactions: [
            { emoji: '😀', count: 1, reacted_by_current_user: false },
          ],
        }
      );
    });

    it('does nothing when the message cannot be found', async () => {
      const context = buildContext();
      context.getters.getConversationById.mockReturnValue({ messages: [] });

      await messageReactionActions.toggleMessageReaction(context, {
        conversationId,
        messageId,
        emoji: '👍',
      });

      expect(context.commit).not.toHaveBeenCalled();
      expect(MessageApi.toggleReaction).not.toHaveBeenCalled();
    });
  });

  describe('#updateMessageReactions', () => {
    it('computes reacted_by_current_user from user_ids against the current user', () => {
      const commit = vi.fn();
      const rootGetters = { getCurrentUser: { id: 7 } };

      messageReactionActions.updateMessageReactions(
        { commit, rootGetters },
        {
          conversationId,
          messageId,
          reactions: [
            { emoji: '👍', count: 2, user_ids: [7, 9] },
            { emoji: '😀', count: 1, user_ids: [9] },
          ],
        }
      );

      expect(commit).toHaveBeenCalledWith(types.UPDATE_MESSAGE_REACTIONS, {
        conversationId,
        messageId,
        reactions: [
          { emoji: '👍', count: 2, reacted_by_current_user: true },
          { emoji: '😀', count: 1, reacted_by_current_user: false },
        ],
      });
    });
  });
});
