# == Schema Information
#
# Table name: message_reactions
#
#  id          :bigint           not null, primary key
#  actor_type  :string           not null
#  emoji       :string           not null
#  external_id :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#  actor_id    :bigint           not null
#  message_id  :bigint           not null
#
# Indexes
#
#  idx_message_reactions_unique_actor                          (message_id,actor_type,actor_id) UNIQUE
#  index_message_reactions_on_account_id                       (account_id)
#  index_message_reactions_on_actor_type_and_actor_id           (actor_type,actor_id)
#  index_message_reactions_on_message_id                       (message_id)
#
# A reaction is state attached to an existing message, never a chat message in its own
# right — creating/removing one must never touch message counts, unread state, or dispatch
# message-created automations/notifications.
class MessageReaction < ApplicationRecord
  belongs_to :account
  belongs_to :message
  belongs_to :actor, polymorphic: true

  validates :emoji, presence: true
  validates :actor_id, uniqueness: { scope: [:message_id, :actor_type] }
  validate :emoji_is_a_single_grapheme, if: -> { emoji.present? }

  before_validation :ensure_account_id

  private

  def ensure_account_id
    self.account_id ||= message&.account_id
  end

  def emoji_is_a_single_grapheme
    errors.add(:emoji, 'must be a single emoji') unless emoji.grapheme_clusters.size == 1
  end
end
