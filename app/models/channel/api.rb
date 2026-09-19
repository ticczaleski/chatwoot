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
    return false unless evolution?

    Array(additional_attributes['provider_capabilities']).include?(capability_name.to_s)
  end

  private

  def ensure_valid_agent_reply_time_window
    return if additional_attributes['agent_reply_time_window'].blank?
    return if additional_attributes['agent_reply_time_window'].to_i.positive?

    errors.add(:agent_reply_time_window, 'agent_reply_time_window must be greater than 0')
  end

  # additional_attributes is a free-form jsonb column shared by every API-inbox use case,
  # so we only enforce shape on the specific keys this provider contract owns, and we treat
  # an invalid present value (wrong type, unknown provider, non-allowlisted capability) as an
  # error rather than silently coercing or ignoring it.
  def ensure_valid_provider
    return unless additional_attributes.key?('provider')

    provider = additional_attributes['provider']
    return if provider.is_a?(String) && SUPPORTED_PROVIDERS.include?(provider)

    errors.add(:additional_attributes, "provider must be one of #{SUPPORTED_PROVIDERS.join(', ')}")
  end

  def ensure_valid_provider_capabilities
    return unless additional_attributes.key?('provider_capabilities')

    capabilities = additional_attributes['provider_capabilities']

    unless capabilities.is_a?(Array) && capabilities.all? { |capability| capability.is_a?(String) }
      errors.add(:additional_attributes, 'provider_capabilities must be an array of capability strings')
      return
    end

    unless evolution?
      errors.add(:additional_attributes, 'provider_capabilities requires provider to be evolution')
      return
    end

    unsupported = capabilities - SUPPORTED_PROVIDER_CAPABILITIES
    return if unsupported.empty?

    errors.add(:additional_attributes, "provider_capabilities contains unsupported values: #{unsupported.join(', ')}")
  end
end
