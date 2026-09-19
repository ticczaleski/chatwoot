# Evolution API Conversation Experience — Compatibility & Rollout Guide

This document supports Phase 8 of `docs/superpowers/plans/2026-09-19-evolution-conversation-experience.md`.
It records the versions this work was built and reviewed against, an operator
checklist for manually verifying end-to-end behavior before enabling reactions
for real traffic, and the staged rollout/rollback procedure.

**Scope note:** this document was written without a running Chatwoot instance,
Evolution instance, WhatsApp connection, or Android/iOS build available in the
authoring environment. The checklists below are unchecked by design — they are
the manual verification steps an operator must run against a real staging
environment before enabling any capability for production traffic. Nothing in
the "Manual verification" sections should be read as "already passed."

## Version matrix

| Component | Repository | Branch | Commit | Notes |
|---|---|---|---|---|
| Chatwoot | `ticczaleski/chatwoot` | `develop` | `da98db144` | Fork base Chatwoot `4.18.0`, tag suffix `-wa` |
| Evolution API | `ticczaleski/evolution-api` | `main` | `9c04c582` | Fork base Evolution `2.3.7`, Baileys provider |
| Android app | chatwoot/chatwoot-mobile-app | — | — | Not verified in this work; see "Mobile compatibility" below |
| iOS app | chatwoot/chatwoot-mobile-app | — | — | Not verified in this work; see "Mobile compatibility" below |

Record the actual mobile app version(s) tested here once smoke testing (below)
has been run, e.g.: `Android 4.6.2 (build 1234)`, `iOS 4.6.0 (build 987)`.

## What each phase changed

| Phase | Chatwoot PR | Evolution PR | Deliverable |
|---|---|---|---|
| 1 | #6 | — | Transparent SVG wallpaper |
| 2 | #6 | — | `Channel::Api#evolution?` / `#provider_capability?` contract |
| 3 | — | #1 | Idempotent outbound delivery, failure→`status:failed` instead of a private note |
| 4 | #7 | #2 | `source_id` registration API, quoted replies resolve via `in_reply_to_external_id` |
| 5 | #8 | — | `MessageReaction` model + `PUT .../messages/:id/reaction` API |
| 6 | #9 | #3 | Webhook + ActionCable reaction events; Evolution reaction bridge (both directions) |
| 7 | #9 | — | Web dashboard reaction controls |
| 8 | this doc | — | Compatibility guide and rollout checklist |

## Capability model

Every capability below is gated by `additional_attributes.provider_capabilities`
on the `Channel::Api` record for a given inbox (`Channel::Api#provider_capability?`,
Phase 2). Nothing in this list is enabled by default for an existing API inbox —
each entry must be added explicitly to `provider_capabilities`.

| Capability | Unlocks | Safe to enable independently? |
|---|---|---|
| `delivery_status` | Evolution maps WhatsApp delivery/read receipts onto Chatwoot's `sent`/`delivered`/`read`/`failed` | Yes — no dependency on the others |
| `quoted_reply` | `source_id` registration + `in_reply_to_external_id` resolution for both directions | Yes — no dependency on the others |
| `reactions` | Reaction persistence, Web UI, and the Evolution reaction bridge (both directions) | Requires both Chatwoot and Evolution to be on the versions in the matrix above; enabling it without the Evolution-side deploy means agent reactions never reach WhatsApp (they still persist safely, but nothing sends) |

Set on the inbox's `Channel::Api` record, e.g. via the dashboard's inbox
settings or directly:

```ruby
channel.update!(
  additional_attributes: {
    'provider' => 'evolution',
    'provider_capabilities' => %w[delivery_status quoted_reply reactions]
  }
)
```

## Manual verification: end-to-end message matrix

Run each row in both directions (agent → WhatsApp contact, and WhatsApp contact
→ agent) against a real Evolution instance connected to a real WhatsApp number,
on a canary/staging account with the `reactions` capability enabled.

- [ ] Plain text message
- [ ] Image attachment
- [ ] Document attachment
- [ ] Audio/voice note
- [ ] Quoted reply to an incoming message
- [ ] Quoted reply to an outgoing (agent-sent) message — this is the case Phase 4
      specifically fixed; confirm the quote resolves correctly on both ends
- [ ] Reaction added (agent side and contact side)
- [ ] Reaction replaced with a different emoji (agent side and contact side)
- [ ] Reaction removed (agent side and contact side)
- [ ] Message delete/unsend
- [ ] Failed send retried from the dashboard (kill the Evolution connection mid-send,
      confirm the message shows `failed` with the provider error, retry succeeds)
- [ ] Read receipt reflected in Chatwoot after the contact reads the message

Additionally:

- [ ] **Duplicate webhook delivery**: replay the same Chatwoot `message_created`
      webhook to Evolution (e.g. resend via a webhook debugging proxy) and confirm
      only one WhatsApp message is sent (Phase 3's `ChatwootDeliveryService.claim`).
- [ ] **Evolution disconnect/reconnect**: disconnect the Evolution WhatsApp session
      mid-conversation, reconnect, and confirm no messages are lost or duplicated,
      and that reactions sent while disconnected are not silently dropped.

## Manual verification: mobile smoke tests

Run against the current production Android and iOS builds. Reactions are a
Web-dashboard-only feature in this phase (Phase 7); native mobile reaction UI
is explicitly out of scope (see "Mobile compatibility" below). The point of
this checklist is to prove older/current mobile clients are **unaffected**.

- [ ] Login
- [ ] Conversation list loads and updates in realtime
- [ ] Opening a conversation that has reaction-bearing messages: the conversation
      loads, messages render normally, no crash, no visible artifact for the
      `reactions` field the app doesn't know about
- [ ] Send a text message from the mobile app
- [ ] Send an attachment from the mobile app
- [ ] Send a quoted reply from the mobile app
- [ ] Message status updates (sent/delivered/read/failed) reflect correctly
- [ ] Push notification received for a new message
- [ ] Resolve and reopen a conversation

## Manual verification: load and ordering

- [ ] Concurrent reactions: two agents react to the same message at the same
      moment with different emojis — confirm the final state is consistent
      (one reaction per agent, no duplicate rows) and the DB unique index
      (`idx_message_reactions_unique_actor`) is not violated under the race
- [ ] Rapid emoji replacement: one agent taps through several quick-reaction
      emojis in succession — confirm only the last one persists and no
      intermediate state flashes back after settling
- [ ] Out-of-order delivery receipts: confirm a `read` receipt arriving before
      a `delivered` receipt for the same message does not regress the status
      (`Messages::StatusUpdateService`'s forward-only transition guard, Phase 3)
- [ ] Webhook replay under load: fire the same reaction webhook twice in quick
      succession and confirm the second is a no-op (`ChatwootDeliveryService.claim`
      keyed by `(instance, chatwootMessageId, operation)`, extended to reactions
      in Phase 6)
- [ ] ActionCable reconnect: disconnect the dashboard's websocket mid-session,
      reconnect, and confirm reaction state resyncs correctly on the next
      message fetch (there is no reaction-specific resync-on-reconnect logic;
      it relies on reactions being embedded in the message JSON on refetch)
- [ ] Confirm unread counts, last message, automations, and reports are
      unaffected by reaction create/update/delete (already covered by
      automated specs in Phase 5 — `spec/models/message_reaction_spec.rb`,
      "no message side effects" — but worth re-confirming against a real
      report dashboard under load)

## Mobile compatibility

- Existing Android and iOS clients continue to operate unchanged: no
  `message_type` or `content_type` enum values were added or changed, no
  existing endpoint's request/response shape was altered (only additive
  fields), and no existing ActionCable event's payload shape changed.
- The mobile apps will simply not render the new `reactions` array on a
  message, nor will they offer a way to create one — this is expected and
  matches the plan's explicit scope ("native reaction controls require a
  separate mobile release").
- No new required permission, deep link, or push-notification payload change
  was introduced.

## Incident: 2026-09-19 — `message_reactions` migration not run before deploy

**What happened:** the Chatwoot image was deployed with the Phase 5–7 code
before the pending migrations (`AddUniqueIndexOnMessagesInboxIdSourceId`,
`CreateMessageReactions`) were applied to the production database. Every
request that rendered a message's JSON — including `GET
.../conversations/:id/messages` used to load older messages when scrolling up
— called `message.reactions_summary` unconditionally
(`app/views/api/v1/models/_message.json.jbuilder:15`), which queries the
`message_reactions` table. Since the table didn't exist yet, this raised
`PG::UndefinedTable: relation "message_reactions" does not exist` and the
endpoint returned 500. Symptom: conversations spun on a loading indicator and
only showed the single most-recent message (delivered separately via
ActionCable, which doesn't go through this jbuilder).

**Why the capability gate didn't protect against this:** the capability model
(above) only gates *behavior* — whether reactions can be created, whether
Evolution relays them. It does not gate the *JSON serialization*, which reads
`reactions_summary` for every message regardless of whether any inbox has the
`reactions` capability enabled. A table dependency introduced by additive code
is not itself "additive" if the migration hasn't run yet.

**Fix applied:** ran `bundle exec rails db:migrate` in production (confirmed
no `(inbox_id, source_id)` duplicates existed first, so both pending
migrations applied cleanly in one pass). Resolved immediately, no data loss,
no code rollback needed.

**Lesson — corrected staged-enablement order below:** migrations must run
**before** (or as part of) deploying the application code that depends on
them, never after. This applies even when the corresponding capability is
disabled for every inbox, because unconditional code paths (like message JSON
serialization) don't check the capability at all.

## Staged enablement

Deploy in this order, verifying each stage before proceeding:

0. **Run pending database migrations before deploying the new application
   code** (not after). For this work specifically: check for existing
   `(inbox_id, source_id)` duplicates first —
   ```sql
   SELECT inbox_id, source_id, COUNT(*)
   FROM messages
   WHERE source_id IS NOT NULL
   GROUP BY inbox_id, source_id
   HAVING COUNT(*) > 1;
   ```
   If empty, run `bundle exec rails db:migrate` in full. If not empty, apply
   only the safe, independent migration first to avoid blocking on the risky
   one (`bundle exec rails db:migrate:up VERSION=20260919000001` for
   `CreateMessageReactions`), then resolve the duplicates before applying
   `AddUniqueIndexOnMessagesInboxIdSourceId` separately.
1. Deploy Chatwoot (Phases 1–5, 7) and Evolution (Phase 3–4) code with **no**
   inbox having `reactions` in `provider_capabilities` yet. This ships the
   wallpaper fix, idempotent delivery, and quoted-reply fix for every existing
   Evolution inbox with zero behavior change to reactions (dark launch).
2. Enable `delivery_status` and `quoted_reply` on one canary Evolution inbox.
   Run the "end-to-end message matrix" above against it (excluding the
   reaction rows).
3. Deploy the Evolution reaction bridge (Evolution PR #3) if not already
   deployed as part of step 1.
4. Enable `reactions` on the same canary inbox only. Run the full message
   matrix above, including reactions, plus the load/ordering checklist.
5. Expand `reactions` to additional inboxes one at a time, monitoring error
   rates on the webhook delivery job queue and the Evolution `reactionMessage`
   call path.

## Rollback

Rollback is capability-first, not code-first — this keeps the additive
database tables/fields in place until the next planned maintenance window,
so no data is lost by rolling back:

1. **Disable `reactions` first**: remove it from the affected inbox's
   `provider_capabilities`. This immediately stops new reaction webhooks from
   being delivered to Evolution and stops the Web UI's reaction controls from
   being usable for that inbox (the backend still accepts the API call, but
   nothing in the dashboard offers it, and Evolution no longer relays out).
   Existing `message_reactions` rows are untouched.
2. If the issue is with delivery reliability or quoted replies rather than
   reactions specifically, disable `quoted_reply` and/or `delivery_status`
   the same way.
3. Only if the issue is in shared code (not gated by a capability — e.g. the
   idempotency claim mechanism itself) does this require a code rollback
   (revert the relevant PR) rather than a capability flip.
4. The `message_reactions` table, the `source_id` unique index, and all
   additive JSON fields are safe to leave in place indefinitely; they impose
   no behavior on inboxes/messages that never use them.

## Final verification record

What was actually run in this authoring environment, and what remains for a
real Ruby/Postgres/mobile environment to confirm:

| Check | Status |
|---|---|
| `pnpm vitest run` (frontend, all files touched across Phases 1–7) | ✅ Run — all passing |
| `pnpm eslint` (frontend, all files touched across Phases 1–7) | ✅ Run — 0 errors, pre-existing unrelated warnings only |
| `pnpm build` (full frontend build) | ❌ Not run in this session (long-running); run before merging to a release branch |
| `bundle exec rspec` (all specs touched across Phases 2, 4, 5, 6) | ❌ Not run — no Ruby/Bundler available in the authoring shell session |
| `bundle exec rubocop` (all Ruby files touched) | ❌ Not run — same limitation |
| Evolution `npx vitest run`, `tsc --noEmit`, `npm run build` | ✅ Run for every Evolution PR (Phases 3, 4, 6) — all passing |
| End-to-end message matrix, mobile smoke tests, load/ordering (above) | ❌ Not run — require a live Chatwoot + Evolution + WhatsApp + mobile app environment this session does not have |

**Before enabling `reactions` for any real customer inbox**, run the Ruby test
suite and rubocop at minimum, and work through the manual checklists above
against a staging environment.
