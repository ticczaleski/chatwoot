# frozen_string_literal: true

require 'rails_helper'

describe Messages::InReplyToMessageBuilder do
  let(:conversation) { create(:conversation) }

  def perform(message, in_reply_to: nil, in_reply_to_external_id: nil)
    described_class.new(
      message: message,
      in_reply_to: in_reply_to,
      in_reply_to_external_id: in_reply_to_external_id
    ).perform
  end

  describe 'bidirectional reply matrix' do
    it 'resolves outgoing -> incoming by internal id' do
      parent = create(:message, conversation: conversation, message_type: :incoming, source_id: 'wa-parent-1')
      reply = build(:message, conversation: conversation, message_type: :outgoing)

      perform(reply, in_reply_to: parent.id)

      expect(reply.content_attributes[:in_reply_to]).to eq(parent.id)
      expect(reply.content_attributes[:in_reply_to_external_id]).to eq('wa-parent-1')
    end

    it 'resolves incoming -> incoming by external (WhatsApp) id' do
      parent = create(:message, conversation: conversation, message_type: :incoming, source_id: 'wa-parent-2')
      reply = build(:message, conversation: conversation, message_type: :incoming)

      perform(reply, in_reply_to_external_id: 'wa-parent-2')

      expect(reply.content_attributes[:in_reply_to]).to eq(parent.id)
      expect(reply.content_attributes[:in_reply_to_external_id]).to eq('wa-parent-2')
    end

    it 'resolves outgoing -> outgoing by internal id' do
      parent = create(:message, conversation: conversation, message_type: :outgoing, source_id: 'wa-parent-3')
      reply = build(:message, conversation: conversation, message_type: :outgoing)

      perform(reply, in_reply_to: parent.id)

      expect(reply.content_attributes[:in_reply_to]).to eq(parent.id)
      expect(reply.content_attributes[:in_reply_to_external_id]).to eq('wa-parent-3')
    end

    it 'resolves incoming -> outgoing by external id, once the outgoing message has a registered source_id' do
      parent = create(:message, conversation: conversation, message_type: :outgoing, source_id: 'wa-parent-4')
      reply = build(:message, conversation: conversation, message_type: :incoming)

      perform(reply, in_reply_to_external_id: 'wa-parent-4')

      expect(reply.content_attributes[:in_reply_to]).to eq(parent.id)
    end

    it 'does not set in_reply_to when the parent message id does not exist' do
      reply = build(:message, conversation: conversation)

      perform(reply, in_reply_to: 0)

      expect(reply.content_attributes[:in_reply_to]).to be_nil
      expect(reply.content_attributes[:in_reply_to_external_id]).to be_nil
    end

    it 'does not set in_reply_to when the external id does not match any message' do
      reply = build(:message, conversation: conversation)

      perform(reply, in_reply_to_external_id: 'does-not-exist')

      expect(reply.content_attributes[:in_reply_to]).to be_nil
    end

    it 'resolves an old parent regardless of pagination, since it queries the database directly' do
      old_parent = create(:message, conversation: conversation, source_id: 'wa-old-parent', created_at: 30.days.ago)
      # Push many newer messages so old_parent would fall off any in-memory "first page".
      create_list(:message, 30, conversation: conversation)
      reply = build(:message, conversation: conversation)

      perform(reply, in_reply_to_external_id: 'wa-old-parent')

      expect(reply.content_attributes[:in_reply_to]).to eq(old_parent.id)
    end

    it 'does not resolve a parent that belongs to a different conversation' do
      other_conversation = create(:conversation, account: conversation.account, inbox: conversation.inbox)
      other_parent = create(:message, conversation: other_conversation, source_id: 'wa-other-conv')
      reply = build(:message, conversation: conversation)

      perform(reply, in_reply_to_external_id: 'wa-other-conv')

      expect(reply.content_attributes[:in_reply_to]).to be_nil
      expect(other_parent.id).to be_present # sanity: the message does exist, just elsewhere
    end
  end

  it 'does nothing when neither in_reply_to nor in_reply_to_external_id is present' do
    reply = build(:message, conversation: conversation)

    perform(reply)

    expect(reply.content_attributes[:in_reply_to]).to be_nil
    expect(reply.content_attributes[:in_reply_to_external_id]).to be_nil
  end
end
