# Adds a database-level guarantee that a given provider (e.g. WhatsApp/Evolution) message id
# is registered at most once per inbox, backing Message's `source_id` uniqueness validation.
#
# IMPORTANT — run before deploying this migration:
# The application-level validation (Message#source_id uniqueness scoped to inbox_id) does not
# protect against duplicates that already exist in production. Before running this migration,
# check for existing duplicates with a read-only query:
#
#   SELECT inbox_id, source_id, COUNT(*)
#   FROM messages
#   WHERE source_id IS NOT NULL
#   GROUP BY inbox_id, source_id
#   HAVING COUNT(*) > 1;
#
# If this returns any rows, STOP: do not run this migration. Produce a cleanup report and
# resolve the duplicates first (do not silently delete or merge messages) — this migration
# will fail with a Postgres uniqueness error if duplicates are present.
class AddUniqueIndexOnMessagesInboxIdSourceId < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :messages, [:inbox_id, :source_id],
              name: 'index_messages_on_inbox_id_and_source_id',
              unique: true,
              where: 'source_id IS NOT NULL',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
