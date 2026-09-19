# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Channel::Api do
  # This validation happens in ApplicationRecord
  describe 'length validations' do
    let(:channel_api) { create(:channel_api) }

    context 'when it validates webhook_url length' do
      it 'valid when within limit' do
        channel_api.webhook_url = 'a' * Limits::URL_LENGTH_LIMIT
        expect(channel_api.valid?).to be true
      end

      it 'invalid when crossed the limit' do
        channel_api.webhook_url = 'a' * (Limits::URL_LENGTH_LIMIT + 1)
        channel_api.valid?
        expect(channel_api.errors[:webhook_url]).to include("is too long (maximum is #{Limits::URL_LENGTH_LIMIT} characters)")
      end
    end
  end

  describe 'provider capabilities' do
    let(:channel_api) { create(:channel_api) }

    context 'when provider is not configured' do
      it 'evolution? is false' do
        expect(channel_api.evolution?).to be(false)
      end

      it 'provider_capability? is false for any capability' do
        expect(channel_api.provider_capability?('reactions')).to be(false)
      end
    end

    context 'when provider_capabilities is set without provider being evolution' do
      it 'does not report the capability as enabled' do
        channel_api.additional_attributes = { 'provider_capabilities' => ['reactions'] }

        expect(channel_api.evolution?).to be(false)
        expect(channel_api.provider_capability?('reactions')).to be(false)
      end

      it 'is invalid, rejecting capabilities on a non-Evolution provider' do
        channel_api.additional_attributes = { 'provider_capabilities' => ['reactions'] }

        expect(channel_api.valid?).to be(false)
        expect(channel_api.errors[:additional_attributes]).to be_present
      end

      it 'is invalid when a non-evolution provider also sets capabilities' do
        channel_api.additional_attributes = { 'provider' => 'not-a-real-provider', 'provider_capabilities' => ['reactions'] }

        expect(channel_api.valid?).to be(false)
      end
    end

    context 'when provider is evolution with capabilities' do
      before do
        channel_api.update!(
          additional_attributes: {
            'provider' => 'evolution',
            'provider_capabilities' => %w[delivery_status quoted_reply reactions]
          }
        )
      end

      it 'evolution? is true' do
        expect(channel_api.evolution?).to be(true)
      end

      it 'recognizes documented capabilities' do
        expect(channel_api.provider_capability?('reactions')).to be(true)
        expect(channel_api.provider_capability?('quoted_reply')).to be(true)
        expect(channel_api.provider_capability?('delivery_status')).to be(true)
      end

      it 'returns false for undocumented capabilities' do
        expect(channel_api.provider_capability?('unknown')).to be(false)
      end
    end

    context 'when provider is an unsupported value' do
      it 'is invalid' do
        channel_api.additional_attributes = { 'provider' => 'not-a-real-provider' }
        expect(channel_api.valid?).to be(false)
        expect(channel_api.errors[:additional_attributes]).to be_present
      end
    end

    context 'when provider is present but not a truthy-looking non-string' do
      it 'rejects false instead of treating it as absent' do
        channel_api.additional_attributes = { 'provider' => false }
        expect(channel_api.valid?).to be(false)
      end

      it 'rejects an empty string instead of treating it as absent' do
        channel_api.additional_attributes = { 'provider' => '' }
        expect(channel_api.valid?).to be(false)
      end

      it 'rejects an empty array' do
        channel_api.additional_attributes = { 'provider' => [] }
        expect(channel_api.valid?).to be(false)
      end

      it 'rejects an empty hash' do
        channel_api.additional_attributes = { 'provider' => {} }
        expect(channel_api.valid?).to be(false)
      end
    end

    context 'when provider_capabilities contains an unknown capability' do
      it 'is invalid' do
        channel_api.additional_attributes = { 'provider' => 'evolution', 'provider_capabilities' => ['reactions', 'not-a-real-capability'] }
        expect(channel_api.valid?).to be(false)
        expect(channel_api.errors[:additional_attributes]).to be_present
      end
    end

    context 'when provider_capabilities is not an array' do
      it 'is invalid' do
        channel_api.additional_attributes = { 'provider' => 'evolution', 'provider_capabilities' => 'reactions' }
        expect(channel_api.valid?).to be(false)
        expect(channel_api.errors[:additional_attributes]).to be_present
      end

      it 'rejects a hash instead of an array' do
        channel_api.additional_attributes = { 'provider' => 'evolution', 'provider_capabilities' => { 'reactions' => true } }
        expect(channel_api.valid?).to be(false)
      end
    end

    context 'when provider_capabilities elements are not strings' do
      it 'rejects symbol elements instead of coercing them' do
        channel_api.additional_attributes = { 'provider' => 'evolution', 'provider_capabilities' => [:reactions] }
        expect(channel_api.valid?).to be(false)
      end

      it 'rejects integer elements instead of coercing them' do
        channel_api.additional_attributes = { 'provider' => 'evolution', 'provider_capabilities' => [1] }
        expect(channel_api.valid?).to be(false)
      end
    end

    context 'when a generic (non-Evolution) API inbox sets unrelated additional_attributes' do
      it 'remains valid without a provider key' do
        channel_api.additional_attributes = { 'agent_reply_time_window' => 60 }
        expect(channel_api.valid?).to be(true)
      end
    end
  end
end
