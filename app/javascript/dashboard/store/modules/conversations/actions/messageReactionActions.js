import MessageApi from '../../../../api/inbox/message';
import types from '../../../mutation-types';

// Removes the current user's own pill (if any), then adds/replaces it with `emoji`.
// An empty `emoji` only removes — it never adds a new pill. Never mutates the message's
// existing array in place; always returns a fresh one, since this feeds a full-replace
// mutation (see UPDATE_MESSAGE_REACTIONS) that both the optimistic update and the eventual
// server/ActionCable reconciliation share, so neither path can leave a duplicate pill behind.
export const applyOptimisticReaction = (reactions, emoji) => {
  const next = (reactions || []).map(reaction => ({ ...reaction }));

  const mineIndex = next.findIndex(
    reaction => reaction.reacted_by_current_user
  );
  if (mineIndex !== -1) {
    next[mineIndex].count -= 1;
    next[mineIndex].reacted_by_current_user = false;
    if (next[mineIndex].count <= 0) {
      next.splice(mineIndex, 1);
    }
  }

  if (!emoji) {
    return next;
  }

  const targetIndex = next.findIndex(reaction => reaction.emoji === emoji);
  if (targetIndex !== -1) {
    next[targetIndex].count += 1;
    next[targetIndex].reacted_by_current_user = true;
  } else {
    next.push({ emoji, count: 1, reacted_by_current_user: true });
  }

  return next;
};

const findMessage = ({ getters }, conversationId, messageId) => {
  const chat = getters.getConversationById(conversationId);
  return (chat?.messages || []).find(message => message.id === messageId);
};

export default {
  async toggleMessageReaction(
    { commit, getters },
    { conversationId, messageId, emoji }
  ) {
    const message = findMessage({ getters }, conversationId, messageId);
    if (!message) return;

    const previousReactions = message.reactions ? [...message.reactions] : [];
    const optimisticReactions = applyOptimisticReaction(
      previousReactions,
      emoji
    );
    commit(types.UPDATE_MESSAGE_REACTIONS, {
      conversationId,
      messageId,
      reactions: optimisticReactions,
    });

    try {
      const response = await MessageApi.toggleReaction(
        conversationId,
        messageId,
        emoji
      );
      commit(types.UPDATE_MESSAGE_REACTIONS, {
        conversationId,
        messageId,
        reactions: response.data.reactions || [],
      });
    } catch (error) {
      // Roll back and re-throw: the caller (a component) is responsible for showing an
      // error toast, matching the convention every other action in this store follows.
      commit(types.UPDATE_MESSAGE_REACTIONS, {
        conversationId,
        messageId,
        reactions: previousReactions,
      });
      throw error;
    }
  },

  // Handles the additive message_reaction_created/updated/deleted ActionCable events. The
  // payload carries { emoji, count, user_ids } per emoji (see ActionCableListener); this
  // computes reacted_by_current_user locally since the backend broadcast has no single
  // "current viewer" to compute that flag for.
  updateMessageReactions(
    { commit, rootGetters },
    { conversationId, messageId, reactions }
  ) {
    const currentUserId = rootGetters.getCurrentUser?.id;

    const normalizedReactions = (reactions || []).map(
      ({ emoji, count, user_ids: userIds }) => ({
        emoji,
        count,
        reacted_by_current_user:
          !!currentUserId && (userIds || []).includes(currentUserId),
      })
    );

    commit(types.UPDATE_MESSAGE_REACTIONS, {
      conversationId,
      messageId,
      reactions: normalizedReactions,
    });
  },
};
