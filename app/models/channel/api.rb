# == Schema Information
#
# Table name: channel_api
#
#  id                    :bigint           not null, primary key
#  additional_attributes :jsonb
#  hmac_mandatory        :boolean          default(FALSE)
#  hmac_token            :string
#  identifier            :string
#  secret                :string
#  webhook_url           :string
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :integer          not null
#
# Indexes
#
#  index_channel_api_on_hmac_token  (hmac_token) UNIQUE
#  index_channel_api_on_identifier  (identifier) UNIQUE
#

class Channel::Api < ApplicationRecord
  include Channelable

  self.table_name = 'channel_api'
  EDITABLE_ATTRS = [:webhook_url, :hmac_mandatory, { additional_attributes: {} }].freeze

  SUPPORTED_PROVIDERS = %w[evolution].freeze
  SUPPORTED_PROVIDER_CAPABILITIES = %w[delivery_status quoted_reply reactions].freeze

  has_secure_token :identifier
  has_secure_token :hmac_token
  include WebhookSecretable
  validate :ensure_valid_agent_reply_time_window
  validate :ensure_valid_provider
  validate :ensure_valid_provider_capabilities
  validates :webhook_url, length: { maximum: Limits::URL_LENGTH_LIMIT }

  def name
    'API'
  end

  def evolution?
    additional_attributes['provider'] == 'evolution'
  end

  def provider_capability?(capability_name)
    Array(additional_attributes['provider_capabilities']).include?(capability_name.to_s)
  end

  private

  def ensure_valid_agent_reply_time_window
    return if additional_attributes['agent_reply_time_window'].blank?
    return if additional_attributes['agent_reply_time_window'].to_i.positive?

    errors.add(:agent_reply_time_window, 'agent_reply_time_window must be greater than 0')
  end

  def ensure_valid_provider
    provider = additional_attributes['provider']
    return if provider.blank?
    return if SUPPORTED_PROVIDERS.include?(provider)

    errors.add(:additional_attributes, "provider must be one of #{SUPPORTED_PROVIDERS.join(', ')}")
  end

  def ensure_valid_provider_capabilities
    capabilities = additional_attributes['provider_capabilities']
    return if capabilities.blank?

    unless capabilities.is_a?(Array)
      errors.add(:additional_attributes, 'provider_capabilities must be an array')
      return
    end

    unsupported = capabilities.map(&:to_s) - SUPPORTED_PROVIDER_CAPABILITIES
    return if unsupported.empty?

    errors.add(:additional_attributes, "provider_capabilities contains unsupported values: #{unsupported.join(', ')}")
  end
end
