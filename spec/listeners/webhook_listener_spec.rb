require 'rails_helper'
describe WebhookListener do
  let(:listener) { described_class.instance }
  let!(:account) { create(:account) }
  let(:report_identity) { Reports::UpdateAccountIdentity.new(account, Time.zone.now) }
  let!(:user) { create(:user, account: account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:contact) { create(:contact, account: account) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: user) }
  let!(:message) do
    create(:message, message_type: 'outgoing',
                     account: account, inbox: inbox, conversation: conversation)
  end
  let!(:message_created_event) { Events::Base.new(event_name, Time.zone.now, message: message) }
  let!(:conversation_created_event) { Events::Base.new(event_name, Time.zone.now, conversation: conversation) }
  let!(:contact_event) { Events::Base.new(event_name, Time.zone.now, contact: contact) }

  describe '#message_created' do
    let(:event_name) { :'message.created' }

    context 'when webhook is not configured' do
      it 'does not trigger webhook' do
        expect(WebhookJob).to receive(:perform_later).exactly(0).times
        listener.message_created(message_created_event)
      end
    end

    context 'when webhook is configured and event is subscribed' do
      it 'triggers the webhook event' do
        webhook = create(:webhook, inbox: inbox, account: account)
        expect(WebhookJob).to receive(:perform_later).with(
          webhook.url, message.webhook_data.merge(event: 'message_created'), :account_webhook,
          secret: webhook.secret, delivery_id: instance_of(String)
        ).once
        listener.message_created(message_created_event)
      end
    end

    context 'when webhook is configured and event is not subscribed' do
      it 'does not trigger the webhook event' do
        create(:webhook, subscriptions: ['conversation_created'], inbox: inbox, account: account)
        expect(WebhookJob).not_to receive(:perform_later)
        listener.message_created(message_created_event)
      end
    end

    context 'when API and webhook access is disabled for the account' do
      before do
        allow(account).to receive(:api_and_webhooks_enabled?).and_return(false)
        allow(message).to receive(:inbox).and_return(inbox)
        allow(inbox).to receive(:account).and_return(account)
      end

      it 'does not trigger account webhooks' do
        create(:webhook, inbox: inbox, account: account)
        expect(WebhookJob).not_to receive(:perform_later)
        listener.message_created(message_created_event)
      end

      it 'still triggers API inbox webhooks' do
        channel_api = create(:channel_api, account: account)
        api_inbox = channel_api.inbox
        api_conversation = create(:conversation, account: account, inbox: api_inbox, assignee: user)
        api_message = create(:message, message_type: 'outgoing', account: account, inbox: api_inbox, conversation: api_conversation)
        api_event = Events::Base.new(event_name, Time.zone.now, message: api_message)
        allow(api_message).to receive(:inbox).and_return(api_inbox)
        allow(api_inbox).to receive(:account).and_return(account)
        expect(WebhookJob).to receive(:perform_later).with(
          channel_api.webhook_url, api_message.webhook_data.merge(event: 'message_created'),
          :api_inbox_webhook, secret: channel_api.secret, delivery_id: instance_of(String)
        ).once
        listener.message_created(api_event)
      end
    end

    context 'when api_and_webhooks feature is disabled on self-hosted' do
      it 'still triggers account webhooks' do
        allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(false)
        account.disable_features!('api_and_webhooks')
        webhook = create(:webhook, inbox: inbox, account: account)

        expect(WebhookJob).to receive(:perform_later).with(
          webhook.url, message.webhook_data.merge(event: 'message_created'), :account_webhook,
          secret: webhook.secret, delivery_id: instance_of(String)
        ).once

        listener.message_created(message_created_event)
      end
    end

    context 'when inbox is an API Channel' do
      it 'triggers webhook if webhook_url is present' do
        channel_api = create(:channel_api, account: account)
        api_inbox = channel_api.inbox
        api_conversation = create(:conversation, account: account, inbox: api_inbox, assignee: user)
        api_message = create(
          :message,
          message_type: 'outgoing',
          account: account,
          inbox: api_inbox,
          conversation: api_conversation
        )
        api_event = Events::Base.new(event_name, Time.zone.now, message: api_message)
        expect(WebhookJob).to receive(:perform_later).with(
          channel_api.webhook_url, api_message.webhook_data.merge(event: 'message_created'),
          :api_inbox_webhook, secret: channel_api.secret, delivery_id: instance_of(String)
        ).once
        listener.message_created(api_event)
      end

      it 'does not trigger webhook if webhook_url is not present' do
        channel_api = create(:channel_api, webhook_url: nil, account: account)
        api_inbox = channel_api.inbox
        api_conversation = create(:conversation, account: account, inbox: api_inbox, assignee: user)
        api_message = create(
          :message,
          message_type: 'outgoing',
          account: account,
          inbox: channel_api.inbox,
          conversation: api_conversation
        )
        api_event = Events::Base.new(event_name, Time.zone.now, message: api_message)
        expect(WebhookJob).not_to receive(:perform_later)
        listener.message_created(api_event)
      end
    end
  end

  describe 'message reaction events' do
    let(:capable_channel_api) { create(:channel_api, account: account) }
    let(:capable_inbox) { capable_channel_api.inbox }
    let(:capable_conversation) { create(:conversation, account: account, inbox: capable_inbox) }
    let(:capable_message) { create(:message, account: account, inbox: capable_inbox, conversation: capable_conversation, source_id: 'WAID:parent-1') }

    before do
      capable_channel_api.update!(additional_attributes: { 'provider' => 'evolution', 'provider_capabilities' => ['reactions'] })
    end

    shared_examples 'a reaction event' do |method_name, event_name|
      it "delivers to a capable API inbox's webhook with the message's source_id" do
        reaction = create(:message_reaction, message: capable_message, actor: user, emoji: '👍')
        event = Events::Base.new(event_name, Time.zone.now, message_reaction: reaction)

        expect(WebhookJob).to receive(:perform_later).with(
          capable_channel_api.webhook_url,
          hash_including(
            event: method_name.to_s,
            message_id: capable_message.id,
            source_id: 'WAID:parent-1',
            emoji: '👍'
          ),
          :api_inbox_webhook,
          secret: capable_channel_api.secret, delivery_id: instance_of(String)
        ).once

        listener.public_send(method_name, event)
      end

      it 'does not deliver to an API inbox that lacks the reactions capability' do
        channel_api = create(:channel_api, account: account)
        api_inbox = channel_api.inbox
        api_conversation = create(:conversation, account: account, inbox: api_inbox)
        api_message = create(:message, account: account, inbox: api_inbox, conversation: api_conversation)
        reaction = create(:message_reaction, message: api_message, actor: user, emoji: '👍')
        event = Events::Base.new(event_name, Time.zone.now, message_reaction: reaction)

        expect(WebhookJob).not_to receive(:perform_later).with(channel_api.webhook_url, any_args)

        listener.public_send(method_name, event)
      end

      it 'still delivers to a subscribed account-level webhook regardless of inbox capability' do
        webhook = create(:webhook, subscriptions: [method_name.to_s], inbox: inbox, account: account)
        reaction = create(:message_reaction, message: message, actor: user, emoji: '👍')
        event = Events::Base.new(event_name, Time.zone.now, message_reaction: reaction)

        expect(WebhookJob).to receive(:perform_later).with(
          webhook.url, hash_including(event: method_name.to_s), :account_webhook,
          secret: webhook.secret, delivery_id: instance_of(String)
        ).once

        listener.public_send(method_name, event)
      end

      it 'acknowledges without error when the parent message no longer exists' do
        reaction = create(:message_reaction, message: capable_message, actor: user, emoji: '👍')
        capable_message.destroy!
        event = Events::Base.new(event_name, Time.zone.now, message_reaction: reaction)

        expect(WebhookJob).not_to receive(:perform_later)
        expect { listener.public_send(method_name, event) }.not_to raise_error
      end
    end

    describe '#message_reaction_created' do
      include_examples 'a reaction event', :message_reaction_created, :'message_reaction.created'
    end

    describe '#message_reaction_updated' do
      include_examples 'a reaction event', :message_reaction_updated, :'message_reaction.updated'
    end

    # #message_reaction_deleted is deliberately NOT covered by the 'a reaction event' shared
    # examples above: MessageReaction#dispatch_deleted_event dispatches plain `reaction_data`
    # instead of the (already destroyed) record, so the event built here must match that shape -
    # not `message_reaction: reaction`, which is exactly the shape that broke delivery in
    # production (see MessageReaction#dispatch_deleted_event for the full explanation).
    describe '#message_reaction_deleted' do
      let(:reaction_data) { { id: 999, emoji: '👍', actor_type: 'User', actor_id: user.id, message_id: capable_message.id } }

      it "delivers to a capable API inbox's webhook using only the dispatched data, with the message already destroyed" do
        event = Events::Base.new(:'message_reaction.deleted', Time.zone.now, reaction_data: reaction_data)

        expect(WebhookJob).to receive(:perform_later).with(
          capable_channel_api.webhook_url,
          hash_including(
            event: 'message_reaction_deleted',
            message_id: capable_message.id,
            source_id: 'WAID:parent-1',
            emoji: '👍'
          ),
          :api_inbox_webhook,
          secret: capable_channel_api.secret, delivery_id: instance_of(String)
        ).once

        listener.message_reaction_deleted(event)
      end

      it 'does not deliver to an API inbox that lacks the reactions capability' do
        channel_api = create(:channel_api, account: account)
        api_inbox = channel_api.inbox
        api_conversation = create(:conversation, account: account, inbox: api_inbox)
        api_message = create(:message, account: account, inbox: api_inbox, conversation: api_conversation)
        event = Events::Base.new(:'message_reaction.deleted', Time.zone.now,
                                  reaction_data: reaction_data.merge(message_id: api_message.id))

        expect(WebhookJob).not_to receive(:perform_later).with(channel_api.webhook_url, any_args)

        listener.message_reaction_deleted(event)
      end

      it 'still delivers to a subscribed account-level webhook regardless of inbox capability' do
        webhook = create(:webhook, subscriptions: ['message_reaction_deleted'], inbox: inbox, account: account)
        event = Events::Base.new(:'message_reaction.deleted', Time.zone.now,
                                  reaction_data: reaction_data.merge(message_id: message.id))

        expect(WebhookJob).to receive(:perform_later).with(
          webhook.url, hash_including(event: 'message_reaction_deleted'), :account_webhook,
          secret: webhook.secret, delivery_id: instance_of(String)
        ).once

        listener.message_reaction_deleted(event)
      end

      it 'acknowledges without error when the parent message no longer exists' do
        event = Events::Base.new(:'message_reaction.deleted', Time.zone.now,
                                  reaction_data: reaction_data.merge(message_id: -1))

        expect(WebhookJob).not_to receive(:perform_later)
        expect { listener.message_reaction_deleted(event) }.not_to raise_error
      end

      # The exact production failure this whole change fixes: a destroyed MessageReaction can
      # no longer be resolved via GlobalID, so nothing here may attempt to re-fetch it - only
      # the still-existing Message may be looked up.
      it 'delivers correctly even though the MessageReaction row no longer exists at all' do
        expect(MessageReaction.find_by(id: reaction_data[:id])).to be_nil
        event = Events::Base.new(:'message_reaction.deleted', Time.zone.now, reaction_data: reaction_data)

        expect(WebhookJob).to receive(:perform_later).once

        expect { listener.message_reaction_deleted(event) }.not_to raise_error
      end
    end
  end

  describe '#conversation_created' do
    let(:event_name) { :'conversation.created' }

    context 'when webhook is not configured' do
      it 'does not trigger webhook' do
        expect(WebhookJob).to receive(:perform_later).exactly(0).times
        listener.conversation_created(conversation_created_event)
      end
    end

    context 'when webhook is configured' do
      it 'triggers webhook' do
        webhook = create(:webhook, inbox: inbox, account: account)
        expect(WebhookJob).to receive(:perform_later).with(
          webhook.url, conversation.webhook_data.merge(event: 'conversation_created'), :account_webhook,
          secret: webhook.secret, delivery_id: instance_of(String)
        ).once
        listener.conversation_created(conversation_created_event)
      end

      it 'includes account details in the conversation payload' do
        webhook = create(:webhook, inbox: inbox, account: account)
        expect(WebhookJob).to receive(:perform_later).with(
          webhook.url,
          hash_including(account: account.webhook_data),
          :account_webhook,
          hash_including(secret: webhook.secret)
        ).once
        listener.conversation_created(conversation_created_event)
      end
    end

    context 'when inbox is an API Channel' do
      it 'triggers webhook if webhook_url is present' do
        channel_api = create(:channel_api, account: account)
        api_inbox = channel_api.inbox
        api_conversation = create(:conversation, account: account, inbox: api_inbox, assignee: user)
        api_event = Events::Base.new(event_name, Time.zone.now, conversation: api_conversation)
        expect(WebhookJob).to receive(:perform_later).with(
          channel_api.webhook_url,
          api_conversation.webhook_data.merge(event: 'conversation_created'),
          :api_inbox_webhook, secret: channel_api.secret, delivery_id: instance_of(String)
        ).once
        listener.conversation_created(api_event)
      end

      it 'does not trigger webhook if webhook_url is not present' do
        channel_api = create(:channel_api, webhook_url: nil, account: account)
        api_inbox = channel_api.inbox
        api_conversation = create(:conversation, account: account, inbox: api_inbox, assignee: user)
        api_event = Events::Base.new(event_name, Time.zone.now, conversation: api_conversation)
        expect(WebhookJob).not_to receive(:perform_later)
        listener.conversation_created(api_event)
      end
    end
  end

  describe '#conversation_updated' do
    let(:custom_attributes) { { test: nil } }
    let!(:conversation_updated_event) do
      Events::Base.new(
        event_name, Time.zone.now,
        conversation: conversation.reload,
        changed_attributes: {
          custom_attributes: [{ test: nil }, { test: 'testing custom attri webhook' }]
        }
      )
    end
    let(:event_name) { :'conversation.updated' }

    context 'when webhook is not configured' do
      it 'does not trigger webhook' do
        expect(WebhookJob).to receive(:perform_later).exactly(0).times
        listener.conversation_updated(conversation_updated_event)
      end
    end

    context 'when webhook is configured' do
      it 'triggers webhook' do
        webhook = create(:webhook, inbox: inbox, account: account)

        conversation.update(custom_attributes: { test: 'testing custom attri webhook' })

        expect(WebhookJob).to receive(:perform_later).with(
          webhook.url,
          conversation.webhook_data.merge(
            event: 'conversation_updated',
            changed_attributes: [
              {
                custom_attributes: {
                  previous_value: { test: nil },
                  current_value: { test: 'testing custom attri webhook' }
                }
              }
            ]
          ),
          :account_webhook,
          secret: webhook.secret, delivery_id: instance_of(String)
        ).once

        listener.conversation_updated(conversation_updated_event)
      end
    end
  end

  describe '#contact_created' do
    let(:event_name) { :'contact.created' }

    context 'when webhook is not configured' do
      it 'does not trigger webhook' do
        expect(WebhookJob).to receive(:perform_later).exactly(0).times
        listener.contact_created(contact_event)
      end
    end

    context 'when webhook is configured' do
      it 'triggers webhook' do
        webhook = create(:webhook, account: account)
        expect(WebhookJob).to receive(:perform_later).with(
          webhook.url, contact.webhook_data.merge(event: 'contact_created'), :account_webhook,
          secret: webhook.secret, delivery_id: instance_of(String)
        ).once
        listener.contact_created(contact_event)
      end
    end
  end

  describe '#contact_updated' do
    let(:event_name) { :'contact.updated' }
    let!(:contact_updated_event) { Events::Base.new(event_name, Time.zone.now, contact: contact, changed_attributes: changed_attributes) }
    let(:changed_attributes) { { 'name' => ['Jane', 'Jane Doe'] } }

    context 'when webhook is not configured' do
      it 'does not trigger webhook' do
        expect(WebhookJob).to receive(:perform_later).exactly(0).times
        listener.contact_updated(contact_updated_event)
      end
    end

    context 'when webhook is configured and there is no changed attributes' do
      let(:changed_attributes) { {} }

      it 'triggers webhook' do
        create(:webhook, account: account)
        expect(WebhookJob).to receive(:perform_later).exactly(0).times
        listener.contact_updated(contact_updated_event)
      end
    end

    context 'when webhook is configured and there are changed attributes' do
      it 'triggers webhook' do
        webhook = create(:webhook, account: account)
        expect(WebhookJob).to receive(:perform_later).with(
          webhook.url,
          contact.webhook_data.merge(
            event: 'contact_updated',
            changed_attributes: [{ 'name' => { :current_value => 'Jane Doe', :previous_value => 'Jane' } }]
          ),
          :account_webhook,
          secret: webhook.secret, delivery_id: instance_of(String)
        ).once
        listener.contact_updated(contact_updated_event)
      end
    end
  end

  describe '#inbox_created' do
    let(:event_name) { :'inbox.created' }
    let!(:inbox_created_event) { Events::Base.new(event_name, Time.zone.now, inbox: inbox) }

    context 'when webhook is not configured' do
      it 'does not trigger webhook' do
        expect(WebhookJob).to receive(:perform_later).exactly(0).times
        listener.inbox_created(inbox_created_event)
      end
    end

    context 'when webhook is configured' do
      it 'triggers webhook' do
        inbox_data = Inbox::EventDataPresenter.new(inbox).webhook_data
        webhook = create(:webhook, account: account, subscriptions: ['inbox_created'])
        expect(WebhookJob).to receive(:perform_later).with(
          webhook.url, inbox_data.merge(event: 'inbox_created'), :account_webhook,
          secret: webhook.secret, delivery_id: instance_of(String)
        ).once
        listener.inbox_created(inbox_created_event)
      end

      it 'includes account details in the inbox payload' do
        webhook = create(:webhook, account: account, subscriptions: ['inbox_created'])
        expect(WebhookJob).to receive(:perform_later).with(
          webhook.url,
          hash_including(account: account.webhook_data),
          :account_webhook,
          hash_including(secret: webhook.secret)
        ).once
        listener.inbox_created(inbox_created_event)
      end
    end
  end

  describe '#inbox_updated' do
    let(:event_name) { :'inbox.updated' }
    let!(:inbox_updated_event) { Events::Base.new(event_name, Time.zone.now, inbox: inbox, changed_attributes: changed_attributes) }
    let(:changed_attributes) { {} }

    context 'when webhook is not configured' do
      it 'does not trigger webhook' do
        expect(WebhookJob).to receive(:perform_later).exactly(0).times
        listener.inbox_updated(inbox_updated_event)
      end
    end

    context 'when webhook is configured and there are no changed attributes' do
      it 'triggers webhook' do
        create(:webhook, account: account, subscriptions: ['inbox_updated'])
        expect(WebhookJob).to receive(:perform_later).exactly(0).times
        listener.inbox_updated(inbox_updated_event)
      end
    end

    context 'when webhook is configured' do
      let(:changed_attributes) { { 'name' => ['Inbox 1', inbox.name] } }

      it 'triggers webhook' do
        webhook = create(:webhook, account: account, subscriptions: ['inbox_updated'])

        inbox_data = Inbox::EventDataPresenter.new(inbox).webhook_data
        changed_attributes_data = [{ 'name' => { 'previous_value': 'Inbox 1', 'current_value': inbox.name } }]

        expect(WebhookJob).to receive(:perform_later).with(
          webhook.url,
          inbox_data.merge(event: 'inbox_updated', changed_attributes: changed_attributes_data),
          :account_webhook,
          secret: webhook.secret, delivery_id: instance_of(String)
        ).once

        listener.inbox_updated(inbox_updated_event)
      end
    end
  end

  describe '#conversation_typing_on' do
    let(:event_name) { :'conversation.typing_on' }
    let!(:typing_event) { Events::Base.new(event_name, Time.zone.now, conversation: conversation, user: user) }

    context 'when webhook is not configured' do
      it 'does not trigger webhook' do
        expect(WebhookJob).not_to receive(:perform_later)
        listener.conversation_typing_on(typing_event)
      end
    end

    context 'when webhook is configured' do
      it 'triggers webhook' do
        webhook = create(:webhook, inbox: inbox, account: account, subscriptions: ['conversation_typing_on'])

        payload = {
          event: 'conversation_typing_on',
          user: user.webhook_data,
          conversation: conversation.webhook_data,
          is_private: false
        }

        expect(WebhookJob).to receive(:perform_later).with(
          webhook.url, payload, :account_webhook,
          secret: webhook.secret, delivery_id: instance_of(String)
        ).once
        listener.conversation_typing_on(typing_event)
      end
    end

    context 'when inbox is an API Channel' do
      it 'triggers webhook if webhook_url is present' do
        channel_api = create(:channel_api, account: account)
        api_inbox = channel_api.inbox
        api_conversation = create(:conversation, account: account, inbox: api_inbox, assignee: user)
        api_event = Events::Base.new(event_name, Time.zone.now, conversation: api_conversation, user: user, is_private: false)

        payload = {
          event: 'conversation_typing_on',
          user: user.webhook_data,
          conversation: api_conversation.webhook_data,
          is_private: false
        }

        expect(WebhookJob).to receive(:perform_later).with(
          channel_api.webhook_url, payload, :api_inbox_webhook,
          secret: channel_api.secret, delivery_id: instance_of(String)
        ).once
        listener.conversation_typing_on(api_event)
      end
    end
  end

  describe '#conversation_typing_off' do
    let(:event_name) { :'conversation.typing_off' }
    let!(:typing_event) { Events::Base.new(event_name, Time.zone.now, conversation: conversation, user: user, is_private: false) }

    context 'when webhook is not configured' do
      it 'does not trigger webhook' do
        expect(WebhookJob).not_to receive(:perform_later)
        listener.conversation_typing_off(typing_event)
      end
    end

    context 'when webhook is configured' do
      it 'triggers webhook' do
        webhook = create(:webhook, inbox: inbox, account: account, subscriptions: ['conversation_typing_off'])

        payload = {
          event: 'conversation_typing_off',
          user: user.webhook_data,
          conversation: conversation.webhook_data,
          is_private: false
        }

        expect(WebhookJob).to receive(:perform_later).with(
          webhook.url, payload, :account_webhook,
          secret: webhook.secret, delivery_id: instance_of(String)
        ).once
        listener.conversation_typing_off(typing_event)
      end
    end
  end
end
