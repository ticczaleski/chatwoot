# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MessageReaction do
  before do
    # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Message).to receive(:reindex_for_search).and_return(true)
    # rubocop:enable RSpec/AnyInstance
  end

  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, account: account, conversation: conversation, inbox: conversation.inbox) }
  let(:agent) { create(:user, account: account) }
  let(:contact) { conversation.contact }

  describe 'validations' do
    it 'is valid with a single-grapheme emoji' do
      reaction = build(:message_reaction, message: message, actor: agent, emoji: '👍')
      expect(reaction.valid?).to be(true)
    end

    it 'is invalid with more than one emoji' do
      reaction = build(:message_reaction, message: message, actor: agent, emoji: '👍👎')
      expect(reaction.valid?).to be(false)
      expect(reaction.errors[:emoji]).to be_present
    end

    it 'is invalid with plain text' do
      reaction = build(:message_reaction, message: message, actor: agent, emoji: 'nice')
      expect(reaction.valid?).to be(false)
    end

    it 'is invalid without an emoji' do
      reaction = build(:message_reaction, message: message, actor: agent, emoji: nil)
      expect(reaction.valid?).to be(false)
    end

    it 'enforces at most one reaction per (message, actor)' do
      create(:message_reaction, message: message, actor: agent, emoji: '👍')
      duplicate = build(:message_reaction, message: message, actor: agent, emoji: '😀')

      expect(duplicate.valid?).to be(false)
      expect(duplicate.errors[:actor_id]).to be_present
    end

    it 'allows the same actor to react to a different message' do
      create(:message_reaction, message: message, actor: agent, emoji: '👍')
      other_message = create(:message, account: account, conversation: conversation, inbox: conversation.inbox)
      other_reaction = build(:message_reaction, message: other_message, actor: agent, emoji: '👍')

      expect(other_reaction.valid?).to be(true)
    end

    it 'allows a contact and an agent to each react to the same message' do
      create(:message_reaction, message: message, actor: agent, emoji: '👍')
      contact_reaction = build(:message_reaction, message: message, actor: contact, emoji: '👍')

      expect(contact_reaction.valid?).to be(true)
    end
  end

  it 'inherits account_id from the message when not explicitly set' do
    reaction = MessageReaction.new(message: message, actor: agent, emoji: '👍')
    reaction.valid?
    expect(reaction.account_id).to eq(message.account_id)
  end

  describe 'emoji replacement' do
    it 'replaces the emoji on the same row via the service, without creating a second row' do
      Messages::ReactionUpdateService.new(message: message, actor: agent, emoji: '👍').perform

      expect do
        Messages::ReactionUpdateService.new(message: message, actor: agent, emoji: '😀').perform
      end.not_to(change { MessageReaction.count })

      reaction = MessageReaction.find_by(message: message, actor: agent)
      expect(reaction.emoji).to eq('😀')
    end
  end

  describe 'empty-emoji removal at the service boundary' do
    it 'destroys the reaction when emoji is blank' do
      Messages::ReactionUpdateService.new(message: message, actor: agent, emoji: '👍').perform

      expect do
        Messages::ReactionUpdateService.new(message: message, actor: agent, emoji: '').perform
      end.to change { MessageReaction.count }.by(-1)
    end

    it 'is a no-op when there is nothing to remove' do
      expect do
        Messages::ReactionUpdateService.new(message: message, actor: agent, emoji: '').perform
      end.not_to(change { MessageReaction.count })
    end
  end

  describe 'cascading deletion' do
    it 'is destroyed when the parent message is destroyed' do
      reaction = create(:message_reaction, message: message, actor: agent, emoji: '👍')

      expect { message.destroy! }.to change { MessageReaction.exists?(reaction.id) }.from(true).to(false)
    end
  end

  describe 'no message side effects' do
    it 'does not change the message count, conversation unread count, or last_activity_at' do
      message.update!(message_type: :incoming)
      conversation.reload

      expect do
        Messages::ReactionUpdateService.new(message: message, actor: agent, emoji: '👍').perform
      end.to not_change { conversation.messages.count }
        .and(not_change { conversation.reload.unread_incoming_messages.count })
        .and(not_change { conversation.reload.last_activity_at })
    end

    it 'does not dispatch message_created events' do
      expect(Rails.configuration.dispatcher).not_to receive(:dispatch).with(Events::Types::MESSAGE_CREATED, any_args)

      Messages::ReactionUpdateService.new(message: message, actor: agent, emoji: '👍').perform
    end
  end

  describe 'event dispatching' do
    it 'dispatches MESSAGE_REACTION_CREATED on creation' do
      expect(Rails.configuration.dispatcher).to receive(:dispatch).with(Events::Types::MESSAGE_REACTION_CREATED, kind_of(Time), hash_including(:message_reaction))

      create(:message_reaction, message: message, actor: agent, emoji: '👍')
    end

    it 'dispatches MESSAGE_REACTION_UPDATED only when the emoji actually changes' do
      reaction = create(:message_reaction, message: message, actor: agent, emoji: '👍')

      expect(Rails.configuration.dispatcher).to receive(:dispatch).with(Events::Types::MESSAGE_REACTION_UPDATED, kind_of(Time), hash_including(:message_reaction))
      reaction.update!(emoji: '😀')
    end

    it 'does not dispatch MESSAGE_REACTION_UPDATED for an unrelated save' do
      reaction = create(:message_reaction, message: message, actor: agent, emoji: '👍')

      expect(Rails.configuration.dispatcher).not_to receive(:dispatch).with(Events::Types::MESSAGE_REACTION_UPDATED, any_args)
      reaction.touch
    end

    it 'dispatches MESSAGE_REACTION_DELETED on destroy' do
      reaction = create(:message_reaction, message: message, actor: agent, emoji: '👍')

      expect(Rails.configuration.dispatcher).to receive(:dispatch).with(Events::Types::MESSAGE_REACTION_DELETED, kind_of(Time), hash_including(:message_reaction))
      reaction.destroy!
    end
  end
end
