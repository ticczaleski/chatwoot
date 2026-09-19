# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Message Reactions API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:conversation) { create(:conversation, inbox: inbox, account: account) }
  let!(:message) { create(:message, conversation: conversation, account: account, inbox: inbox) }

  before { create(:inbox_member, inbox: inbox, user: agent) }

  def reaction_url(msg = message, conv = conversation)
    "/api/v1/accounts/#{account.id}/conversations/#{conv.display_id}/messages/#{msg.id}/reaction"
  end

  describe 'PUT .../messages/:id/reaction' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        put reaction_url, params: { emoji: '👍' }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when an authenticated agent reacts' do
      it 'creates a reaction attributed to the agent' do
        put reaction_url, params: { emoji: '👍' }, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        reaction = MessageReaction.find_by(message: message, actor: agent)
        expect(reaction.emoji).to eq('👍')
      end

      it 'replaces the same reaction instead of creating a second one' do
        put reaction_url, params: { emoji: '👍' }, headers: agent.create_new_auth_token, as: :json

        expect do
          put reaction_url, params: { emoji: '😀' }, headers: agent.create_new_auth_token, as: :json
        end.not_to(change { MessageReaction.count })

        expect(MessageReaction.find_by(message: message, actor: agent).emoji).to eq('😀')
      end

      it 'removes the reaction when emoji is blank' do
        put reaction_url, params: { emoji: '👍' }, headers: agent.create_new_auth_token, as: :json

        expect do
          put reaction_url, params: { emoji: '' }, headers: agent.create_new_auth_token, as: :json
        end.to change { MessageReaction.count }.by(-1)
        expect(response).to have_http_status(:success)
      end

      it 'rejects an invalid (multi-character) emoji without persisting it' do
        expect do
          put reaction_url, params: { emoji: 'not-an-emoji' }, headers: agent.create_new_auth_token, as: :json
        end.not_to(change { MessageReaction.count })

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns not found when the message does not exist' do
        put "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{message.id + 999_999}/reaction",
            params: { emoji: '👍' }, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when the conversation belongs to another account' do
      let(:other_account) { create(:account) }
      let(:other_inbox) { create(:inbox, account: other_account) }
      let!(:other_conversation) { create(:conversation, inbox: other_inbox, account: other_account) }
      let!(:other_message) { create(:message, conversation: other_conversation, account: other_account, inbox: other_inbox) }

      it 'returns not found and does not leak the reaction across accounts' do
        put "/api/v1/accounts/#{account.id}/conversations/#{other_conversation.display_id}/messages/#{other_message.id}/reaction",
            params: { emoji: '👍' }, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
        expect(MessageReaction.exists?(message: other_message)).to be(false)
      end
    end

    context 'when the reaction is provider-originated (message_type: incoming, relaying a contact reaction)' do
      let(:api_channel) { create(:channel_api, account: account) }
      let(:capable_inbox) { create(:inbox, channel: api_channel, account: account) }
      let!(:capable_conversation) { create(:conversation, inbox: capable_inbox, account: account) }
      let!(:capable_message) { create(:message, conversation: capable_conversation, account: account, inbox: capable_inbox) }

      before do
        create(:inbox_member, inbox: capable_inbox, user: agent)
        api_channel.update!(additional_attributes: { 'provider' => 'evolution', 'provider_capabilities' => ['reactions'] })
      end

      it 'attributes the reaction to the conversation contact, not the authenticated agent' do
        put reaction_url(capable_message, capable_conversation),
            params: { emoji: '👍', message_type: 'incoming' }, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        reaction = MessageReaction.find_by(message: capable_message)
        expect(reaction.actor).to eq(capable_conversation.contact)
      end

      context 'when the API inbox does not have the reactions capability' do
        before { api_channel.update!(additional_attributes: {}) }

        it 'returns forbidden and does not create a reaction' do
          put reaction_url(capable_message, capable_conversation),
              params: { emoji: '👍', message_type: 'incoming' }, headers: agent.create_new_auth_token, as: :json

          expect(response).to have_http_status(:forbidden)
          expect(MessageReaction.exists?(message: capable_message)).to be(false)
        end
      end

      context 'when the inbox is not an API inbox at all' do
        it 'returns forbidden for a provider-originated reaction' do
          put reaction_url, params: { emoji: '👍', message_type: 'incoming' }, headers: agent.create_new_auth_token, as: :json

          expect(response).to have_http_status(:forbidden)
          expect(MessageReaction.exists?(message: message)).to be(false)
        end
      end
    end
  end
end
