# Creates, replaces, or removes the given actor's reaction on a message. An empty emoji
# removes the reaction. Never creates a message, never touches conversation/message state.
class Messages::ReactionUpdateService
  pattr_initialize [:message!, :actor!, :emoji]

  def perform
    ActiveRecord::Base.transaction do
      reaction = locked_existing_reaction || new_reaction

      if emoji.blank?
        reaction.destroy! if reaction.persisted?
        next nil
      end

      reaction.emoji = emoji
      reaction.save!
      reaction
    end
  end

  private

  # Locks the row (if it exists) for the duration of the transaction so concurrent
  # replace/remove calls for the same (message, actor) tuple cannot race each other.
  #
  # `polymorphic_name`, not `class.name`: a SuperAdmin is a `User` STI subclass, and the
  # actor_type column is populated from the STI base class ("User") whenever the polymorphic
  # association itself sets it (on create). Querying by the raw subclass name here would never
  # find that row, so removing/replacing a SuperAdmin's own reaction would silently no-op
  # instead of touching the existing record, and re-adding it would then hit the (message,
  # actor_type, actor_id) uniqueness validation against the row this lookup failed to find.
  def locked_existing_reaction
    MessageReaction.lock.find_by(message_id: message.id, actor_type: actor.class.polymorphic_name, actor_id: actor.id)
  end

  def new_reaction
    MessageReaction.new(message: message, actor: actor, account_id: message.account_id)
  end
end
