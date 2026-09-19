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
    end
  end
end
