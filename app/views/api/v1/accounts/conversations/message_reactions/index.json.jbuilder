json.array! @message_reactions do |reaction|
  json.id reaction.id
  json.emoji reaction.emoji
  json.actor_type reaction.actor_type
  json.actor_id reaction.actor_id
  json.created_at reaction.created_at.to_i
end
