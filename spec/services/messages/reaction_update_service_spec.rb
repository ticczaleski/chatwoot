# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Messages::ReactionUpdateService do
  before do
    # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Message).to receive(:reindex_for_search).and_return(true)
    # rubocop:enable RSpec/AnyInstance
  end

  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, account: account, conversation: conversation, inbox: conversation.inbox) }
  let(:agent) { create(:user, account: account) }

  it 'creates a reaction for a new actor' do
    described_class.new(message: message, actor: agent, emoji: '👍').perform

    expect(MessageReaction.find_by(message: message, actor: agent).emoji).to eq('👍')
  end

  it 'replaces an existing reaction with a new emoji' do
    described_class.new(message: message, actor: agent, emoji: '👍').perform
    described_class.new(message: message, actor: agent, emoji: '😀').perform

    expect(MessageReaction.where(message: message, actor: agent).count).to eq(1)
    expect(MessageReaction.find_by(message: message, actor: agent).emoji).to eq('😀')
  end

  it 'removes the existing reaction when emoji is blank' do
    described_class.new(message: message, actor: agent, emoji: '👍').perform
    described_class.new(message: message, actor: agent, emoji: '').perform

    expect(MessageReaction.find_by(message: message, actor: agent)).to be_nil
  end

  # A SuperAdmin is a `User` STI subclass. The polymorphic `actor` association stores
  # actor_type as the STI base class ("User") on write, so the lookup that finds an existing
  # reaction to replace/remove must key off the same base class - not the literal STI subclass
  # name - or it silently fails to find a SuperAdmin's own reaction every time.
  context 'when the actor is a SuperAdmin (User STI subclass)' do
    let(:super_admin) { create(:super_admin) }

    it 'replaces its own reaction instead of raising a uniqueness error' do
      described_class.new(message: message, actor: super_admin, emoji: '👍').perform

      expect do
        described_class.new(message: message, actor: super_admin, emoji: '😀').perform
      end.not_to raise_error

      expect(MessageReaction.where(message: message, actor: super_admin).count).to eq(1)
      expect(MessageReaction.find_by(message: message, actor: super_admin).emoji).to eq('😀')
    end

    it 'removes its own reaction when emoji is blank' do
      described_class.new(message: message, actor: super_admin, emoji: '👍').perform
      described_class.new(message: message, actor: super_admin, emoji: '').perform

      expect(MessageReaction.find_by(message: message, actor: super_admin)).to be_nil
    end
  end
end
