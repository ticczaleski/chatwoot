class Api::V1::Accounts::Conversations::MessageReactionsController < Api::V1::Accounts::Conversations::BaseController
  before_action :ensure_provider_capable_inbox, if: :provider_originated?

  def index
    @message_reactions = message.message_reactions.includes(:actor)
  end

  def update
    Messages::ReactionUpdateService.new(message: message, actor: actor, emoji: permitted_params[:emoji]).perform
    @message = message
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    render_could_not_create_error(error_message(e))
  end

  private

  def message
    @message ||= @conversation.messages.find(permitted_params[:id])
  end

  # For a provider relaying a WhatsApp contact's own reaction (message_type: 'incoming', the
  # same convention MessageBuilder already uses for contact-originated messages), the actor is
  # the conversation's contact regardless of which service token authenticated the request.
  # Otherwise it is whoever is calling the API (an agent, or an agent bot).
  def actor
    provider_originated? ? @conversation.contact : (Current.user || @resource)
  end

  def provider_originated?
    permitted_params[:message_type] == 'incoming'
  end

  def ensure_provider_capable_inbox
    return if @conversation.inbox.api? && @conversation.inbox.channel.provider_capability?('reactions')

    render json: { error: 'Reactions are not enabled for this inbox' }, status: :forbidden
  end

  def error_message(error)
    return error.record.errors.full_messages.join(', ') if error.respond_to?(:record) && error.record

    error.message
  end

  def permitted_params
    params.permit(:id, :emoji, :message_type)
  end
end
