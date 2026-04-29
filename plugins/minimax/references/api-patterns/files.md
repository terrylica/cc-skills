# MiniMax Files API

> **Aggregated copy** of `~/own/amonic/minimax/api-patterns/files.md` (source-of-truth — read-only, source iter-19). Sibling-doc refs resolve within `references/api-patterns/`; fixture refs use absolute source paths (most fixtures are not aggregated per [`../INDEX.md`](../INDEX.md)). Aggregated 2026-04-29 (iter-10).

Verified 2026-04-29 with full upload/list/delete cycle. **Headline finding: Files API IS ACCESSIBLE on Plus-High-Speed plan with no rate-limit issues — second non-chat-completion feature available without plan upgrade (after embeddings).** Different from OpenAI's `/v1/files`: MiniMax uses sub-resource naming (`/v1/files/list`, `/v1/files/upload`, `/v1/files/delete`).

This iter's full discovery contrasts with iter-15 (TTS plan-gated), iter-16 (video plan-gated), and iter-17/18 (embeddings throttled) — the first non-chat-completion endpoint with full read/write functionality on this plan tier.

## Test setup

5 probes total, in 3 phases:

### Phase 1: Path discovery (parallel)

| Probe | Method | Path                    | Result   |
| ----- | ------ | ----------------------- | -------- |
| F1    | GET    | `/v1/files`             | HTTP 404 |
| F2    | POST   | `/v1/files` (multipart) | HTTP 404 |

### Phase 2: Path sweep (parallel, 7 candidates)

After F1+F2 both 404'd, swept alternative paths:

| Path                 | Status  | Notes                                  |
| -------------------- | ------- | -------------------------------------- |
| `/v1/file`           | 404     |                                        |
| `/v1/file_upload`    | 404     |                                        |
| `/v1/file_list`      | 404     |                                        |
| `/v1/file/list`      | 404     |                                        |
| `/v1/file/upload`    | 404     |                                        |
| `/v1/upload`         | 404     |                                        |
| **`/v1/files/list`** | **200** | ✅ `{"files": [], "base_resp": {...}}` |

The sub-path `/v1/files/list` is the correct list endpoint. **MiniMax uses sub-resource naming for files** (different from `/v1/files` collection-resource style).

### Phase 3: Full CRUD verification

| Probe | Method | Path               | Body / Form                                      | Outcome                           |
| ----- | ------ | ------------------ | ------------------------------------------------ | --------------------------------- |
| F3    | POST   | `/v1/files/upload` | multipart: `file=test.txt` + `purpose=retrieval` | HTTP 200, file_id 392728805122169 |
| F4    | GET    | `/v1/files/list`   | (none)                                           | HTTP 200, file in list            |
| F5    | POST   | `/v1/files/delete` | JSON: `{"file_id": 392728805122169}`             | HTTP 200, success                 |

## Headline findings

### Finding 1: 🆕 Sub-resource naming pattern — fourth MiniMax-native URL convention

After 4 endpoint families discovered, MiniMax has used FOUR distinct URL conventions:

| Pattern                         | Examples                                                     | Discovered  |
| ------------------------------- | ------------------------------------------------------------ | ----------- |
| OpenAI-compat (full)            | `/v1/chat/completions`, `/v1/models`                         | iter-1, 2   |
| OpenAI-compat URL only          | `/v1/embeddings` (body uses `texts`, not `input`)            | iter-17     |
| MiniMax-native abbreviated+ver  | `/v1/t2a_v2`                                                 | iter-15     |
| MiniMax-native full-word        | `/v1/video_generation`                                       | iter-16     |
| **MiniMax-native sub-resource** | **`/v1/files/list`, `/v1/files/upload`, `/v1/files/delete`** | **iter-19** |

When migrating OpenAI code, **`/v1/files` collection style does NOT work** — must use sub-resource verbs. This is more REST-y than the other patterns (closer to gRPC RPC-style than RESTful resource-collection).

### Finding 2: 🎉 Files API is fully accessible on Plus-High-Speed plan

Unlike TTS (iter-15) and video (iter-16) which both plan-gate, the files API works end-to-end:

- `/v1/files/upload` accepts multipart/form-data uploads
- `/v1/files/list` returns the user's file collection
- `/v1/files/delete` deletes by file_id

No `2061 "plan not support model"` errors anywhere. **No rate-limit issues either** (unlike embeddings' 1002 RPM throttle that persisted across 10-minute waits).

This is a **major positive finding** for amonic services contemplating RAG-with-attachments — Karakeep document storage, Linkwarden article archives, Gmail attachment indexing, etc. can all use the MiniMax files API as a content store.

### Finding 3: file_id is a 64-bit integer (NOT OpenAI's string format)

```json
"file_id": 392728805122169
```

OpenAI uses string IDs like `file-abc123` (object prefix + random alphanumeric). MiniMax uses bare 64-bit integers. **Type implications**:

- JavaScript's `Number` precision is 53 bits — file IDs above 2^53 = 9007199254740992 will lose precision if naively parsed as numbers. Use `BigInt` or string-handling for safety.
- JSON parsers in Python/Go/Rust handle this fine (arbitrary precision), but JavaScript clients are at risk.

**Production rule**: when consuming MiniMax file_id in a JS frontend, parse as string from the JSON response (`JSON.parse(text, reviver)` or post-process), not as Number.

### Finding 4: Upload response includes useful metadata

```json
{
  "file": {
    "file_id": 392728805122169,
    "bytes": 69,
    "created_at": 1777434869,
    "filename": "test.txt",
    "purpose": "retrieval"
  },
  "base_resp": { "status_code": 0, "status_msg": "success" }
}
```

Fields:

- `file_id`: 64-bit integer ID
- `bytes`: file size in bytes
- `created_at`: Unix epoch UTC seconds
- `filename`: preserved from upload
- `purpose`: echoed from request

This is sufficient for client-side bookkeeping without an extra retrieve call.

### Finding 5: List response shape uses `files` key (NOT OpenAI's `data`)

```json
{
  "files": [
    {"file_id": ..., "bytes": ..., "created_at": ..., "filename": ..., "purpose": ...}
  ],
  "base_resp": {"status_code": 0, "status_msg": "success"}
}
```

OpenAI's `/v1/files` returns `{"object": "list", "data": [{"object": "file", ...}]}`. MiniMax uses `files` array directly with no `object` discriminator. **Migration code needs body translation**.

### Finding 6: Delete uses POST with JSON body (NOT DELETE method)

```json
POST /v1/files/delete
{"file_id": 392728805122169}
```

Returns:

```json
{
  "file_id": 392728805122169,
  "base_resp": { "status_code": 0, "status_msg": "success" }
}
```

OpenAI uses `DELETE /v1/files/{file_id}` (RESTful path-based). MiniMax uses `POST` to a sub-resource verb with body. This is consistent with the sub-resource naming pattern but unusual for files APIs (most use DELETE method).

### Finding 7: `purpose: "retrieval"` is accepted (other values likely exist)

Tested only `"retrieval"`. OpenAI's purposes include `assistants`, `vision`, `batch`, `fine-tune`. MiniMax may have different valid values; likely candidates:

- `"retrieval"` ✅ confirmed
- `"fine-tune"` (if MiniMax offers fine-tuning)
- `"assistants"` (if MiniMax has an assistants-style API)
- `"vision"` (probably not, since iter-13 confirmed M2.7 doesn't have vision)

Untested follow-ups for T3.x.

### Finding 8: 6th-category compat pattern holds (HTTP 200 + base_resp envelope)

All 5 probes that hit the actual endpoint returned HTTP 200 with `base_resp` envelope (success or error indicated via `status_code`). Consistent with iter-15 (TTS) and iter-16 (video) on native MiniMax endpoints.

## Implications

### For amonic services contemplating RAG-with-attachments

**Files API works today on Plus-High-Speed plan.** Practical applications:

1. **Karakeep document storage**: Save full HTML/PDF of bookmarked pages to MiniMax files API; reference by file_id when retrieving for tag-generation
2. **Linkwarden archive uploads**: Push article snapshots; let MiniMax store; retrieve content for summarization
3. **Gmail attachment indexing**: Upload PDF/DOCX attachments; later use file_id for content-based search
4. **General multi-turn context**: Upload large documents once, reference in chat completions later (depending on whether `/v1/chat/completions` accepts file_ids — needs T3.x probe)

The `purpose: "retrieval"` indicates content is intended for retrieval-augmented generation. Useful for the actual RAG pipeline.

### Storage limits unknown

iter-19 didn't test:

- Maximum file size per upload
- Maximum total storage per account
- Retention policy (do files expire?)
- Pricing per byte stored

Production code should be defensive — check `bytes` returned vs expected; handle errors gracefully.

### For migration testing from OpenAI

Three translation axes needed:

```python
# OpenAI code:
client.files.create(file=open("doc.pdf", "rb"), purpose="assistants")
client.files.list()
client.files.delete(file_id="file-abc123")

# MiniMax equivalent:
httpx.post(f"{BASE}/v1/files/upload", files={"file": ("doc.pdf", content)},
           data={"purpose": "retrieval"}, headers=auth)  # different URL
httpx.get(f"{BASE}/v1/files/list", headers=auth)  # different URL
httpx.post(f"{BASE}/v1/files/delete", json={"file_id": 392728805122169},
           headers=auth)  # different URL + body, NOT DELETE method
```

URL routing AND body shape AND HTTP method translation needed per operation.

## Idiomatic patterns

### Pattern: Files API client wrapper

```python
import httpx
from typing import TypedDict

class FileMetadata(TypedDict):
    file_id: int
    bytes: int
    created_at: int  # Unix epoch UTC
    filename: str
    purpose: str

class MiniMaxFiles:
    def __init__(self, api_key: str, base: str = "https://api.minimax.io"):
        self._auth = {"Authorization": f"Bearer {api_key}"}
        self._base = base

    def upload(self, file_bytes: bytes, filename: str,
               purpose: str = "retrieval", content_type: str = "application/octet-stream") -> FileMetadata:
        resp = httpx.post(
            f"{self._base}/v1/files/upload",
            headers=self._auth,
            files={"file": (filename, file_bytes, content_type)},
            data={"purpose": purpose},
            timeout=60,
        )
        parsed = resp.json()
        if parsed["base_resp"]["status_code"] != 0:
            raise RuntimeError(f"Upload failed: {parsed['base_resp']['status_msg']}")
        return parsed["file"]

    def list(self) -> list[FileMetadata]:
        resp = httpx.get(f"{self._base}/v1/files/list", headers=self._auth, timeout=30)
        parsed = resp.json()
        if parsed["base_resp"]["status_code"] != 0:
            raise RuntimeError(f"List failed: {parsed['base_resp']['status_msg']}")
        return parsed["files"]

    def delete(self, file_id: int) -> None:
        resp = httpx.post(
            f"{self._base}/v1/files/delete",
            headers=self._auth,
            json={"file_id": file_id},
            timeout=30,
        )
        parsed = resp.json()
        if parsed["base_resp"]["status_code"] != 0:
            raise RuntimeError(f"Delete failed: {parsed['base_resp']['status_msg']}")
```

### Pattern: Defensive cleanup in tests

Always delete uploaded test files at end of test runs to avoid quota bloat:

```python
def test_upload_and_delete():
    files = MiniMaxFiles(api_key)
    file_id = files.upload(b"test content", "test.txt")["file_id"]
    try:
        # ... test logic that uses file_id ...
        listing = files.list()
        assert any(f["file_id"] == file_id for f in listing)
    finally:
        files.delete(file_id)  # always clean up
```

## Open questions for follow-up

- **What `purpose` values are valid?** Only `"retrieval"` confirmed.
- **Maximum file size?** 69 bytes uploaded successfully; need boundary test.
- **Maximum file count per account?** Storage quota unknown.
- **File retention?** Do files expire?
- **Content retrieval endpoint?** Likely `GET /v1/files/retrieve_content?file_id=X` or similar — untested.
- **Metadata retrieval for a single file?** `/v1/files/retrieve` perhaps — untested.
- **Can `/v1/chat/completions` reference uploaded file_ids in messages?** Critical for RAG flows. Likely a content type or message reference field. Test in T3.x.
- **Pricing per byte stored?** Not visible in probes.

## Provenance

| Probe | URL                | Method | Outcome                                                       |
| ----- | ------------------ | ------ | ------------------------------------------------------------- |
| F1    | `/v1/files`        | GET    | HTTP 404                                                      |
| F2    | `/v1/files`        | POST   | HTTP 404                                                      |
| F3    | `/v1/files/upload` | POST   | HTTP 200, file_id 392728805122169                             |
| F4    | `/v1/files/list`   | GET    | HTTP 200, file in list                                        |
| F5    | `/v1/files/delete` | POST   | HTTP 200, file deleted; subsequent /list returned empty array |

Plus 7 candidate paths swept in Phase 2 (only `/v1/files/list` returned non-404).

Fixtures:

- [`fixtures/files-F1-GET-files-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/files-F1-GET-files-2026-04-28.json)
- [`fixtures/files-F2-POST-file-upload-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/files-F2-POST-file-upload-2026-04-28.json)
- [`fixtures/files-followup-path-sweep-summary-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/files-followup-path-sweep-summary-2026-04-28.json)
- [`fixtures/files-F3-POST-upload-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/files-F3-POST-upload-2026-04-28.json)
- [`fixtures/files-F4-GET-list-after-upload-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/files-F4-GET-list-after-upload-2026-04-28.json)
- [`fixtures/files-F5-POST-delete-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/files-F5-POST-delete-2026-04-28.json)

Verifier: autonomous-loop iter-19. Total ~13 API calls (2 initial 404 + 7 path sweep + 1 upload + 1 list + 1 delete + 1 verify-list).
