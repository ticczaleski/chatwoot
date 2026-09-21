# Mobile PDF delivery design

## Goal

Make document attachments, especially PDFs, reliably downloadable and previewable in the Chatwoot Android and iOS apps without embedding expiring storage URLs in message payloads. Preserve the existing attachment contract for web and provider integrations.

## Scope

This work is delivered as two independent changes:

1. The Chatwoot backend publishes a stable, non-redirecting document URL and complete MIME metadata.
2. The Chatwoot mobile app downloads documents to a deterministic, valid local filename, reports actionable failures, and declares Android PDF viewer visibility.

Outbound provider integrations continue using `Attachment#download_url` and its existing short-lived direct storage URL. Images, audio, and video retain their current URL behavior.

## Backend design

For attachments whose `file_type` is `file`, `Attachment#file_metadata` will use the Active Storage proxy route rather than `file_url` or a direct service URL. The proxy route gives mobile clients a stable Chatwoot URL, returns the bytes without a storage redirect, and avoids an arbitrary seven-day lifetime. Other callers of `download_url` remain unchanged.

The API attachment partial will serialize the existing `content_type` value alongside `extension`. This makes the REST response consistent with `push_event_data` and gives clients an authoritative MIME type.

Model and request/view tests will establish that document URLs use the proxy route, do not call the direct download URL, and include `content_type`. Existing image behavior will remain covered.

## Mobile design

`FileBubblePreview` will receive the attachment identifier, extension, MIME type, and URL. It will derive a cache key from stable attachment metadata, sanitize the extension, and never use a signed URL segment as a filesystem filename.

Downloading starts when the user presses the document. The app writes to a temporary cache path, requires a successful HTTP status and a non-empty file, then moves the completed file to its final cache path before calling `FileViewer.open`. An existing non-empty cached file may be opened directly. Failed or partial downloads are removed and can be retried.

Download and preview failures remain distinct. The user sees a localized, stage-appropriate message, while diagnostics retain the underlying error, response status, platform, MIME type, sanitized URL origin/path, and local path. Secrets and signed query parameters must not be logged. Existing project error-reporting conventions will be used; no new telemetry dependency is introduced.

The Android generated manifest will declare visibility for an `ACTION_VIEW` handler with `application/pdf`, as required by `react-native-file-viewer` for modern Android targets. iOS continues using Quick Look through the same library.

## Failure behavior

- A non-2xx response is a download failure and is never passed to the native viewer.
- A zero-byte or missing downloaded file is a download failure.
- A failed temporary download leaves no valid cache entry.
- A native viewer failure is reported separately from a download failure.
- A second press retries a failed download.
- Component unmounting or attachment changes do not update stale React state.

## Compatibility

The backend change is additive except for the document `data_url` value. Its shape remains a normal HTTPS URL. Web clients continue opening it normally. Provider integrations that require direct service URLs are unaffected because they call `download_url` explicitly.

The mobile change accepts both the new proxy URL and older redirect/direct URLs. Cache identity is based on attachment metadata rather than URL shape, so regenerated storage signatures do not create duplicate files.

## Verification

Backend verification covers the attachment model specs and API attachment serialization specs, followed by the relevant RuboCop invocation.

Mobile verification covers filename/cache-path normalization, successful and failed downloads, partial-file cleanup, retry behavior, cached-file opening, distinct preview errors, TypeScript/lint checks, and inspection of the generated Android manifest. Manual verification uses one PDF and one text file on both Android and iOS; Android additionally verifies behavior with and without an installed PDF handler.

## Delivery

The backend and mobile changes live on separate branches and are suitable for separate pull requests. Neither branch will include generated build products, credentials, downloaded attachments, or unrelated working-tree changes.
