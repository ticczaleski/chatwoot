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
- [x] Image attachment — verified 2026-09-21 against a real WhatsApp contact
      (+5555999703107), agent → contact, after fixing the `FRONTEND_URL`
      certificate issue documented below (see "Incident: 2026-09-21 — media
      attachments never reached WhatsApp")
- [x] Document attachment — verified 2026-09-21 alongside the image, same
      contact and fix, **for WhatsApp delivery only**; opening/downloading a
      document attachment from the Chatwoot mobile app itself is a separate,
      still-open problem — see the addendum on "Incident: 2026-09-21 — media
      attachments never reached WhatsApp" below
- [ ] Audio/voice note
- [ ] Quoted reply to an incoming message
- [ ] Quoted reply to an outgoing (agent-sent) message — this is the case Phase 4
      specifically fixed; confirm the quote resolves correctly on both ends
- [x] Reaction added (agent side and contact side) — verified 2026-09-21 in
      production against a real WhatsApp contact (+555599703107), after fixing
      the two issues above (capability not configured, then the `instanceId`
      bug — see "Incident: 2026-09-21" below)
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

## Incident: 2026-09-21 — agent reactions never reached WhatsApp (Evolution-side bug)

**What happened:** after the 2026-09-19 migration fix, manual verification found
the `reactions` capability wasn't even enabled yet on the two production
Evolution inboxes (`additional_attributes` was `{}` — never configured). Once
enabled, the WhatsApp-contact → Chatwoot direction worked immediately, but
agent reactions sent from the Chatwoot dashboard still never reached WhatsApp.
Evolution's logs showed the webhook arriving and being accepted, but every
attempt logged `Could not resolve WhatsApp key for chatwoot message X;
acknowledging without retry`, even for a message confirmed to exist (with the
matching WhatsApp key) in Evolution's own local `Message` table.

**Root cause:** Evolution's `ChatwootRouter` webhook route
(`POST /chatwoot/webhook/:instanceName`) builds its `instance` object from the
URL's `:instanceName` param alone (`RouterBroker#dataValidate` never resolves
`instanceId`). The pre-existing `message_created` handling path patches this
in — `instance.instanceId = waInstance.instanceId`, right after resolving the
running instance — before using it for anything DB-keyed. The reaction
webhook handler added in Phase 6 (`handleReactionWebhook`) resolved
`waInstance` the same way but never copied its `instanceId` onto `instance`,
so `getMessageByKeyId`'s `WHERE "instanceId" = ${instance.instanceId}`
predicate always compared against `undefined` and silently matched zero rows
— not a Chatwoot-side or capability-model problem at all.

**Why this wasn't caught by the reaction bridge's unit tests:** every existing
test mocked `getMessageByKeyId` directly, bypassing the real SQL predicate
construction (and therefore the missing `instanceId` assignment) entirely.

**Fix applied:** [ticczaleski/evolution-api#5](https://github.com/ticczaleski/evolution-api/pull/5)
adds the same `instance.instanceId = waInstance.instanceId` assignment to
`handleReactionWebhook`, plus a regression test that constructs a bare
`{instanceName}` instance (matching what the real webhook route produces) and
asserts `getMessageByKeyId` receives the resolved `instanceId`. Verified live
against both production inboxes after redeploying the image: reactions now
relay correctly in both directions.

**Lesson:** any Evolution code path entered via `receiveWebhook` (the
Chatwoot → Evolution HTTP webhook) needs a manual `instanceId` resolution step
before it can rely on it for a DB lookup — `instance` is not a fully-populated
`InstanceDto` on that path the way it is on paths driven by Baileys' own
`messages.upsert` handler (which does construct one with both fields from the
start). A unit test that mocks past this assignment can't catch a missing one;
verifying the reaction bridge end-to-end against a real deployment (not just
its unit tests) is what actually surfaced this.

## Incident: 2026-09-21 — media attachments never reached WhatsApp (infra, not code)

**What happened:** sending an image or PDF attachment from the Chatwoot
dashboard silently failed to reach WhatsApp — no error surfaced in Chatwoot's
UI (a document attachment even *looked* fine there, since Chatwoot's own
preview never needed to re-fetch the file), but the message's `source_id`
stayed empty, meaning Evolution never registered a WhatsApp key for it at all.

**Root cause:** Evolution's outbound attachment path
(`ChatwootService#sendAttachment`) fetches the attachment's `data_url` — an
Active Storage URL built from Chatwoot's `FRONTEND_URL`
(`https://chat-ti.cczaleski.com.br` at the time) — before it can hand the
bytes to Baileys. That hostname is **not a Cloudflare-managed zone** (its NS
was never delegated to Cloudflare; DNS stayed on registro.br), so Traefik has
no way to obtain a real certificate for it and falls back to a self-signed
one. Every browser on the corporate network trusts that self-signed cert via
an internally-distributed root CA, so nobody watching from a browser ever
saw a problem — but Evolution's Node.js process has no such CA installed, so
its `fetch`/`axios` call rejected the connection with `DEPTH_ZERO_SELF_SIGNED_CERT`
and the attachment was never sent. Reproduced directly: `curl`/`node https.get`
from inside the Evolution container against the old hostname failed
identically; the same call against a Cloudflare-backed hostname succeeded.

**Why this wasn't specific to reactions or any code in this plan's phases:**
it affects *any* outbound attachment on *any* inbox, unconditionally — a pure
infrastructure/certificate gap, not a capability-gated code path. It was only
discovered now because media hadn't been manually verified end-to-end before
(see "Manual verification" above being originally unchecked-by-design).

**Fix applied:** `chat-ti.zaleski.pro` already had a working Cloudflare
Tunnel route to `chatwoot-ti_rails:3000` (planned but never pointed at, per
the stack file's own comments) with a valid, publicly-trusted certificate
(Cloudflare's edge, issued by Google Trust Services). Switched Chatwoot's
`FRONTEND_URL` to that domain — every attachment URL Chatwoot generates now
resolves to it, so Evolution's fetch succeeds without needing any custom CA
installed anywhere. The original `chat-ti.cczaleski.com.br` router/hostname
was left in place (still self-signed) for continuity; only `FRONTEND_URL`
(and therefore what new attachment links point to) changed.

**Lesson:** a self-signed certificate that every human's browser silently
trusts (via a pre-installed corporate root CA) is invisible to anyone testing
by hand, but every non-browser HTTP client (this integration, curl, any
future automation) will reject it outright. Any URL a server-to-server
integration must fetch — not just click — needs a certificate chain that
client actually trusts out of the box; "works for everyone in the office" is
not evidence a service-to-service fetch will work.

**Addendum, same day — document attachments still fail in the Chatwoot mobile
app (unresolved, likely upstream):** fixing the certificate got WhatsApp
delivery of images and documents working end-to-end, and got images
rendering correctly in the Chatwoot mobile app too. Documents did not follow:
opening/downloading a PDF from the mobile app first got stuck loading
indefinitely (`app/models/attachment.rb`'s `file_metadata` was sending a
redirect-based `file_url` for every non-image `file_type`), then — after
switching documents to the direct, non-redirecting `download_url`
(`ticczaleski/chatwoot#16`) — failed instead with a client-side "File load
error" (`download_url`'s signed link defaults to a 5-minute expiry, wrong for
something embedded in a message's JSON that a client may only open minutes
later; fixed with a 1-week expiry in `ticczaleski/chatwoot#17`). After both
fixes, the mobile app **still** shows "File load error" for documents, while
images keep working and the same URL succeeds from `curl` with the correct
`200`/`Content-Type`/`Content-Disposition`.

Traced the failure into the mobile app's own source
(`chatwoot/chatwoot-mobile-app`, `FileBubble.tsx`):

```js
ReactNativeBlobUtil.config({ overwrite: true, path: localFilePath, fileCache: true })
  .fetch('GET', fileSrc)
  .then(_result => setFileDownload(false))
  .catch(() => {
    Alert.alert('File load error');
  });
```

This is a blanket `catch` — any failure (network, TLS, timeout, non-2xx)
surfaces the exact same alert with no underlying detail, so nothing server-side
can distinguish which of those it actually is from the outside. Since the
same URL is independently confirmed working via `curl` and in-app for images,
the remaining gap is specific to this document-download code path in the
mobile app itself, not this integration's inbox/channel code.

**Further isolation (same day):** ruled out two more candidate causes. This is
a strong client-side isolation, not a confirmed root cause — see the
correction below for exactly what it does and doesn't prove:

- **Filename** (the failing PDFs' names had spaces/special characters):
  uploaded a document with a plain ASCII filename (`Google.pdf`, stored as
  `Google-40.pdf`) — same "File load error".
- **File type vs. plain text**: a `.txt` attachment through the *exact same*
  `FileBubblePreview` component opened normally on the same device, same
  network, same session — so this isn't "documents are broken," specifically
  PDFs are.
- **The file/URL/network path itself**: opened the same signed `download_url`
  for the `Google-40.pdf` attachment directly in the phone's own mobile
  browser (same WiFi, same device) — opened normally.

**Correction (external review):** the code only ever emits the literal alert
text `"File load error"` from `ReactNativeBlobUtil.fetch()`'s `.catch()` (the
download/local-write step) — a failure in `FileViewer.open()` (the native
PDF-preview step) instead shows `"Not able to preview file"`. So the observed
alert text already narrows this to the download/write step, *before* any
native PDF viewer is ever invoked — the phrasing above conflating both steps
into one "flow" overstated what was actually isolated. The browser test
proves the file, URL, certificate, and this account/device/network combination
are all fine; it does not by itself distinguish *which part* of
`ReactNativeBlobUtil.fetch()`'s work (the HTTP request, the local file write,
or something in how `fileSrc`'s filename/query shape is parsed) is failing,
since a browser's HTTP stack, storage, and native download handling are not
the same code as `react-native-blob-util`'s. Concrete, actionable next steps
for whoever picks this up in the mobile app (`chatwoot/chatwoot-mobile-app`):
replace the swallowed `.catch(() => Alert.alert(...))` with actual error
detail (message/stack, HTTP status, response headers, local file existence
and size after the write) rather than relying solely on `adb logcat` — the
JS-level rejection reason it discards may not surface natively at all; stop
deriving the local cache filename by splitting the signed `fileSrc` URL
(fragile for any signed-URL shape, proxy or otherwise) and instead build it
from `attachment.id` + `extension`/`contentType`, which the app already has
in its message payload; and add the Android 11+ `<queries>` manifest entry
for `application/pdf` that `react-native-file-viewer` requires under
`targetSdkVersion: 36` (present in this app), which is a separate, likely
*next* failure once the download/write step itself is fixed.

On this repo's side, PR #18 replaced both #16's redirect and #17's
arbitrarily-expiring signed URL with ActiveStorage's proxy route
(`rails_storage_proxy_url`) — no redirect, and a `signed_id` that never
expires, which is strictly better than either prior attempt regardless of
whether it changes the mobile outcome. No further action taken here on the
mobile app itself; that repository is out of this integration's reach from
this session.

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
