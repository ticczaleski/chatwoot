# Mobile PDF Delivery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lock the merged Chatwoot attachment API contract with a request spec and make the mobile app download, validate, cache, diagnose, and open PDF attachments reliably.

**Architecture:** The backend task adds only contract coverage on top of PR #18. The mobile task moves filesystem/network behavior into a tested document utility, leaves the bubble responsible for UI state and native preview, and adds an idempotent Expo config plugin for Android PDF-handler visibility.

**Tech Stack:** Rails/RSpec/Jbuilder; React Native 0.86, Expo 57, TypeScript, Jest, `react-native-blob-util`, `react-native-file-viewer`, Expo config plugins, Sentry.

**Spec:** `docs/superpowers/specs/2026-09-21-mobile-pdf-delivery-design.md`

## Global Constraints

- PR #18 already owns backend production behavior; do not modify `Attachment`, its Jbuilder partial, or URL selection.
- Preserve existing URL behavior for image, audio, video, and outbound provider integrations.
- Derive mobile cache identity without signed query parameters and never log those parameters.
- Write downloads to a partial file, require HTTP 2xx plus a non-empty file, then move atomically to the final cache path.
- Keep download and native-preview failures distinct and retryable.
- Do not add a production dependency or change native iOS behavior.
- Do not fork, push, or open a pull request for `chatwoot-mobile-app` without new explicit authorization.
- Update only the English source locale for new mobile copy; translation synchronization remains upstream's responsibility.

## Review Focus

- A refreshed signed URL for the same attachment must reuse the same cache file rather than create a duplicate.
- Two installations/accounts with the same numeric attachment ID must not share a cache entry when their URL origin/path differs.
- A `200` response whose file is missing or zero bytes must be rejected and its partial file removed.
- Query parameters containing storage signatures must never appear in Sentry context.
- Android manifest generation must add exactly one PDF `ACTION_VIEW` query across repeated prebuild runs.

---

### Task 1: Backend attachment API contract coverage

**Repository:** `ticczaleski/chatwoot`, branch based on current `origin/develop` after PR #18.

**Files:**
- Modify: `spec/controllers/api/v1/accounts/contacts/attachments_controller_spec.rb`

**Interfaces:**
- Consumes: `GET /api/v1/accounts/:account_id/contacts/:contact_id/attachments` and PR #18's `data_url`/`content_type` serialization.
- Produces: request-level regression coverage; no production interface changes.

- [ ] **Step 1: Rebase the isolated backend branch on merged PR #18**

Run:

```powershell
git fetch origin --prune
git rebase origin/develop
```

Expected: the branch contains merge commit `506c032cb` or a newer `origin/develop`, and only the design/plan commits are branch-local.

- [ ] **Step 2: Add the failing API assertions**

Extend the existing administrator example `serialises the conversation display id as conversation_id` so it selects the returned attachment and asserts the actual contract:

```ruby
expect(attachment).to include(
  'id',
  'message_id',
  'data_url',
  'file_type',
  'content_type',
  'created_at',
  'sender'
)
expect(attachment['content_type']).to eq('image/png')
expect(attachment['data_url']).to be_present
```

Before adding the assertions, confirm the `:with_attachment` factory's literal MIME type. Use that literal rather than deriving the expectation from `push_event_data`.

- [ ] **Step 3: Verify the test protects the serializer**

Temporarily run the test against the parent of PR #18's serializer change, or temporarily remove only `json.content_type` in the isolated worktree, then run:

```powershell
bundle exec rspec spec/controllers/api/v1/accounts/contacts/attachments_controller_spec.rb
```

Expected: FAIL because `content_type` is absent. Restore the merged production file immediately afterward.

- [ ] **Step 4: Run the request spec against PR #18**

Initialize rbenv when available, then run:

```powershell
bundle exec rspec spec/controllers/api/v1/accounts/contacts/attachments_controller_spec.rb
```

Expected: all examples PASS.

- [ ] **Step 5: Run scoped Ruby lint**

```powershell
bundle exec rubocop spec/controllers/api/v1/accounts/contacts/attachments_controller_spec.rb
```

Expected: exit 0 with no offenses.

- [ ] **Step 6: Commit the backend test**

```powershell
git add spec/controllers/api/v1/accounts/contacts/attachments_controller_spec.rb
git commit -m "test(attachments): cover MIME metadata in API response"
```

---

### Task 2: Mobile document download utility

**Repository:** local clone of `chatwoot/chatwoot-mobile-app`, on a new local branch based on `origin/develop`.

**Files:**
- Create: `src/utils/documentAttachment.ts`
- Create: `src/utils/specs/documentAttachment.spec.ts`

**Interfaces:**
- Consumes:
  - `DocumentSource = { id: number; messageId: number; dataUrl: string; extension?: string | null; contentType?: string | null }`
  - `ReactNativeBlobUtil.fs.dirs.CacheDir`, `.exists`, `.stat`, `.mv`, and `.unlink`
  - `ReactNativeBlobUtil.config({ path, fileCache: true, overwrite: true }).fetch('GET', dataUrl)`
  - `expo-crypto.digestStringAsync` for a stable cache namespace.
- Produces:
  - `documentCachePath(source: DocumentSource): Promise<string>` returning a stable cache path whose extension comes from metadata.
  - `prepareDocument(source: DocumentSource): Promise<string>` returning an absolute, non-empty cached file path.
  - `documentDisplayName(source: DocumentSource): string` returning a decoded query-free label.
  - `documentErrorContext(source: DocumentSource, localPath?: string)` returning Sentry-safe metadata without URL query/fragment.

- [ ] **Step 1: Write failing tests for stable and isolated cache paths**

In `documentAttachment.spec.ts`, mock the native filesystem/fetch boundary and Expo Crypto. Add literal cases proving:

```ts
expect(await documentCachePath(sourceWithSignatureA)).toEqual(
  await documentCachePath(sourceWithSignatureB),
);
expect(await documentCachePath(sourceAtOriginOne)).not.toEqual(
  await documentCachePath(sourceAtOriginTwo),
);
expect(await documentCachePath(pdfSource)).toMatch(/\.pdf$/);
expect(await documentCachePath(maliciousExtensionSource)).not.toContain('../');
```

Use identical `id`/`messageId` for the cross-origin case. The Crypto mock must hash its input, not return one constant for every source.

- [ ] **Step 2: Run the utility tests and observe RED**

```powershell
pnpm test -- --runInBand src/utils/specs/documentAttachment.spec.ts
```

Expected: FAIL because `documentAttachment.ts` and its exports do not exist.

- [ ] **Step 3: Implement normalized identity, extension, label, and safe diagnostics**

Implement these rules in `documentAttachment.ts`:

```ts
const normalizedRemoteIdentity = (dataUrl: string) => {
  const parsed = new URL(dataUrl);
  return `${parsed.origin}${parsed.pathname}`;
};

const sanitizeExtension = (extension?: string | null) => {
  const normalized = extension?.replace(/^\./, '').toLowerCase();
  return normalized && /^[a-z0-9]{1,10}$/.test(normalized) ? normalized : 'bin';
};
```

Hash `${normalizedRemoteIdentity(dataUrl)}:${messageId}:${id}` and build `CacheDir/document_<hash>.<extension>`. `documentErrorContext` may expose `remoteOrigin`, `remotePath`, attachment IDs, content type, extension, and local path, but never `search`, `hash`, or the original URL.

- [ ] **Step 4: Add failing tests for download validation and cleanup**

Cover these literal outcomes:

- cached path exists and `stat.size > 0`: return it without fetch;
- cached path exists but has size `0`: remove it and download again;
- HTTP `200` plus positive partial-file size: move partial to final and return final;
- HTTP `403`/`500`: reject with status and remove partial;
- HTTP `200` plus missing or zero-byte partial: reject and remove partial;
- rejected native fetch: preserve the original error and remove partial;
- a retry after rejection starts a new fetch rather than caching the rejection;
- diagnostic context omits `X-Amz-Signature`, token values, query, and fragment.

- [ ] **Step 5: Run the expanded utility tests and observe RED**

```powershell
pnpm test -- --runInBand src/utils/specs/documentAttachment.spec.ts
```

Expected: path tests PASS; download tests FAIL because `prepareDocument` is not implemented.

- [ ] **Step 6: Implement atomic preparation**

Implement `prepareDocument` with this sequence:

```ts
const finalPath = await documentCachePath(source);
if (await isNonEmptyFile(finalPath)) return finalPath;

const partialPath = `${finalPath}.partial`;
await removeIfPresent(partialPath);
try {
  const response = await ReactNativeBlobUtil.config({
    path: partialPath,
    fileCache: true,
    overwrite: true,
  }).fetch('GET', source.dataUrl);
  const status = response.info().status;
  if (status < 200 || status >= 300) throw new Error(`Document download failed with status ${status}`);
  if (!(await isNonEmptyFile(partialPath))) throw new Error('Downloaded document is empty');
  await ReactNativeBlobUtil.fs.mv(partialPath, finalPath);
  return finalPath;
} catch (error) {
  await removeIfPresent(partialPath);
  throw error;
}
```

Do not add retries or timeouts; a later user press is the retry boundary.

- [ ] **Step 7: Run utility tests and lint**

```powershell
pnpm test -- --runInBand src/utils/specs/documentAttachment.spec.ts
pnpm eslint src/utils/documentAttachment.ts src/utils/specs/documentAttachment.spec.ts
```

Expected: both commands exit 0.

- [ ] **Step 8: Commit the utility**

```powershell
git add src/utils/documentAttachment.ts src/utils/specs/documentAttachment.spec.ts
git commit -m "fix(attachments): prepare documents in a stable cache"
```

---

### Task 3: Mobile file bubble state, errors, and metadata wiring

**Files:**
- Modify: `src/screens/chat-screen/components/message-components/FileBubble.tsx`
- Modify: `src/screens/chat-screen/components/message-components/MessageAttachments.tsx`
- Create: `src/screens/chat-screen/components/message-components/specs/FileBubble.spec.tsx`
- Modify: `src/i18n/en.json`
- Modify: `package.json`
- Modify: `pnpm-lock.yaml`

**Interfaces:**
- Consumes: Task 2's `DocumentSource`, `prepareDocument`, `documentDisplayName`, and `documentErrorContext`; `FileViewer.open(path)`; `Sentry.captureException`.
- Produces: `FileBubblePreview` props `{ fileSrc, attachmentId, messageId, extension, contentType, isComposed?, variant }`; press-driven download/open UI.

- [ ] **Step 1: Declare the existing React test renderer as a direct test dependency**

The Expo/Jest dependency graph already resolves `react-test-renderer@19.2.3` and its types in the lockfile, but the component spec must not rely on an undeclared transitive package. Run:

```powershell
pnpm add --save-dev react-test-renderer@19.2.3 @types/react-test-renderer@19.1.0
```

Expected: only `package.json` and `pnpm-lock.yaml` dependency metadata changes; no production dependency is added.

- [ ] **Step 2: Write failing component tests**

Mock only the native boundaries (`prepareDocument`, `FileViewer.open`, Sentry) and render the real bubble. Cover:

- mounting does not download;
- pressing calls `prepareDocument` with literal attachment metadata, then opens the returned path;
- a second press after a download rejection calls `prepareDocument` again;
- download rejection shows `CONVERSATION.FILE_DOWNLOAD_ERROR`, reports stage `download`, and does not call `FileViewer.open`;
- preview rejection shows `CONVERSATION.FILE_PREVIEW_ERROR` and reports stage `preview`;
- while one press is pending, another press does not start a duplicate operation;
- state is not updated after unmount.

- [ ] **Step 3: Run the component tests and observe RED**

```powershell
pnpm test -- --runInBand src/screens/chat-screen/components/message-components/specs/FileBubble.spec.tsx
```

Expected: FAIL because the current component downloads on mount and lacks the metadata props/state separation.

- [ ] **Step 4: Add English source strings**

Under the existing `CONVERSATION` object in `src/i18n/en.json`, add:

```json
"FILE_DOWNLOAD_ERROR": "Could not download this file. Please try again.",
"FILE_PREVIEW_ERROR": "Could not open this file on your device."
```

Do not edit generated/community locale files.

- [ ] **Step 5: Wire attachment metadata into the bubble**

Update `MessageAttachments.tsx`:

```tsx
<FileBubblePreview
  attachmentId={attachment.id}
  messageId={attachment.messageId}
  fileSrc={attachment.dataUrl}
  extension={attachment.extension}
  contentType={attachment.contentType}
  isComposed
  variant={variant}
/>
```

Update `FileBubbleProps` and `FilePreviewProps` to match the produced interface exactly.

- [ ] **Step 6: Implement press-driven download and preview**

Remove the mount-time `useEffect` download. On press:

1. return early when already loading;
2. set loading;
3. await `prepareDocument(source)`;
4. await `FileViewer.open(path)`;
5. catch download and preview separately;
6. call `Sentry.captureException(error, { tags: { attachmentStage }, extra: documentErrorContext(...) })`;
7. show the matching localized alert;
8. clear loading in `finally` only while mounted.

Use a ref cleanup effect solely to prevent state updates after unmount. Keep the press enabled after failure so the user can retry.

- [ ] **Step 7: Run component and utility tests**

```powershell
pnpm test -- --runInBand src/screens/chat-screen/components/message-components/specs/FileBubble.spec.tsx src/utils/specs/documentAttachment.spec.ts
```

Expected: all examples PASS.

- [ ] **Step 8: Run scoped lint and TypeScript checks**

```powershell
pnpm eslint src/screens/chat-screen/components/message-components/FileBubble.tsx src/screens/chat-screen/components/message-components/MessageAttachments.tsx src/screens/chat-screen/components/message-components/specs/FileBubble.spec.tsx src/utils/documentAttachment.ts src/utils/specs/documentAttachment.spec.ts
pnpm exec tsc --noEmit
```

Expected: both commands exit 0.

- [ ] **Step 9: Commit the UI integration**

```powershell
git add src/screens/chat-screen/components/message-components/FileBubble.tsx src/screens/chat-screen/components/message-components/MessageAttachments.tsx src/screens/chat-screen/components/message-components/specs/FileBubble.spec.tsx src/i18n/en.json package.json pnpm-lock.yaml
git commit -m "fix(attachments): download documents when opened"
```

---

### Task 4: Android PDF handler visibility

**Files:**
- Create: `with-android-file-viewer-queries.js`
- Create: `with-android-file-viewer-queries.spec.js`
- Modify: `app.config.ts`

**Interfaces:**
- Consumes: Expo `withAndroidManifest` and the generated manifest object.
- Produces: one Android `<queries><intent>` entry for `android.intent.action.VIEW` plus MIME type `application/pdf`.

- [ ] **Step 1: Write failing idempotence tests for the config plugin**

Export the mutation function separately from the run-once plugin so the test can call it with a manifest fixture. Assert that:

- an empty manifest gains the PDF VIEW query;
- an existing unrelated query remains unchanged;
- invoking the mutation twice leaves exactly one matching PDF VIEW intent.

- [ ] **Step 2: Run the plugin test and observe RED**

```powershell
pnpm test -- --runInBand with-android-file-viewer-queries.spec.js
```

Expected: FAIL because the plugin does not exist.

- [ ] **Step 3: Implement and register the Expo config plugin**

Use `withAndroidManifest` and `createRunOncePlugin`. Match an existing intent by both action and MIME type before appending this structure:

```js
{
  action: [{ $: { 'android:name': 'android.intent.action.VIEW' } }],
  data: [{ $: { 'android:mimeType': 'application/pdf' } }],
}
```

Preserve all existing `manifest.queries` entries. Register `'./with-android-file-viewer-queries.js'` in `app.config.ts` beside the other local Android plugins.

- [ ] **Step 4: Run plugin tests and inspect generated configuration**

```powershell
pnpm test -- --runInBand with-android-file-viewer-queries.spec.js
pnpm exec expo config --type prebuild
```

Expected: test PASS; generated Android manifest configuration contains one PDF VIEW query.

- [ ] **Step 5: Run lint**

```powershell
pnpm eslint with-android-file-viewer-queries.js with-android-file-viewer-queries.spec.js app.config.ts
```

Expected: exit 0.

- [ ] **Step 6: Commit Android configuration**

```powershell
git add with-android-file-viewer-queries.js with-android-file-viewer-queries.spec.js app.config.ts
git commit -m "fix(android): declare PDF viewer visibility"
```

---

### Task 5: Final verification and local handoff

**Files:**
- Review only; no planned production changes.

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces: two verified local branches and a report of remaining device checks; no push or PR.

- [ ] **Step 1: Verify the backend branch from a clean status**

```powershell
git status --short
bundle exec rspec spec/controllers/api/v1/accounts/contacts/attachments_controller_spec.rb spec/models/attachment_spec.rb
bundle exec rubocop spec/controllers/api/v1/accounts/contacts/attachments_controller_spec.rb
git diff origin/develop...HEAD --check
```

Expected: clean status, tests/lint exit 0, and no whitespace errors.

- [ ] **Step 2: Verify the mobile branch**

```powershell
git status --short
pnpm test -- --runInBand src/utils/specs/documentAttachment.spec.ts src/screens/chat-screen/components/message-components/specs/FileBubble.spec.tsx with-android-file-viewer-queries.spec.js
pnpm eslint src/utils/documentAttachment.ts src/utils/specs/documentAttachment.spec.ts src/screens/chat-screen/components/message-components/FileBubble.tsx src/screens/chat-screen/components/message-components/MessageAttachments.tsx src/screens/chat-screen/components/message-components/specs/FileBubble.spec.tsx with-android-file-viewer-queries.js with-android-file-viewer-queries.spec.js app.config.ts
pnpm exec tsc --noEmit
pnpm exec expo config --type prebuild
git diff origin/develop...HEAD --check
```

Expected: clean status and all commands exit 0.

- [ ] **Step 3: Inspect branch scope**

```powershell
git log --oneline origin/develop..HEAD
git diff --stat origin/develop...HEAD
```

Expected: backend contains only documentation plus the API regression test; mobile contains only document-download, tests, English source copy, and Android query configuration.

- [ ] **Step 4: Record manual device verification as pending unless devices are available**

On Android and iOS, test a PDF and TXT attachment twice (first download and cached open). On Android, additionally test a device with no PDF handler and one with a handler. Record exact app/OS versions and alert/log output for any failure.

- [ ] **Step 5: Stop before external publication**

Report both local branch names, commits, automated verification results, and pending device checks. Ask for explicit authorization before any fork, remote push, or pull request involving `chatwoot-mobile-app`.
