# Reactions are state attached to an existing message, never a chat message themselves.
# At most one reaction per (message, actor) — replacing an emoji updates the same row.
class CreateMessageReactions < ActiveRecord::Migration[7.1]
  def change
    create_table :message_reactions do |t|
      t.references :account, null: false
      t.references :message, null: false
      t.string :actor_type, null: false
      t.bigint :actor_id, null: false
      t.string :emoji, null: false
      t.string :external_id

      t.timestamps
    end

    add_index :message_reactions, [:message_id, :actor_type, :actor_id],
              unique: true, name: 'idx_message_reactions_unique_actor'
    add_index :message_reactions, [:actor_type, :actor_id]
  end
end
