# Provider Compatibility Matrix

Tested Anthropic-compatible providers for use with claude-code-proxy (2026-02-22).

---

## Tested Providers

### MiniMax M2.5-highspeed

| Field              | Value                                          |
| ------------------ | ---------------------------------------------- |
| Endpoint           | `https://api.minimax.io/anthropic/v1/messages` |
| Auth               | API key via `Authorization: Bearer`            |
| Base URL for proxy | `https://api.minimax.io/anthropic`             |
| Streaming          | Supported                                      |
| Token counting     | Not supported (proxy returns 501)              |

**Quirks**:

1. **Model name in response**: Returns `"model": "MiniMax-M2.5"` instead of the requested model name. Cosmetic only; Claude Code handles this gracefully.

2. **Extra `thinking` block**: MiniMax includes a `thinking` content block with a `signature` field in responses. Claude Code ignores unknown content block types.

3. **Extra `base_resp` field**: Responses include a `base_resp` metadata object not present in Anthropic responses. No functional impact.

4. **API key source**: 1Password at `op://Claude Automation/MiniMax API - High-Speed Plan/password`

### Real Anthropic

| Field              | Value                                                                  |
| ------------------ | ---------------------------------------------------------------------- |
| Endpoint           | `https://api.anthropic.com/v1/messages`                                |
| Auth               | OAuth Bearer token + `anthropic-beta: oauth-2025-04-20` OR `x-api-key` |
| Base URL for proxy | `https://api.anthropic.com`                                            |
| Streaming          | Supported                                                              |
| Token counting     | Supported (`/v1/messages/count_tokens`)                                |

**Notes**:

- OAuth requires the `anthropic-beta: oauth-2025-04-20` header (see CCP-02)
- API key auth uses `x-api-key` header (not `Authorization: Bearer`)
- Both auth methods supported simultaneously (proxy tries OAuth first)

---

## Generic Provider Requirements

To be compatible with claude-code-proxy, a provider must:

1. **Support `/v1/messages` endpoint** with Anthropic's request/response schema
2. **Support streaming** via `text/event-stream` SSE format
3. **Accept `Authorization: Bearer {api_key}`** for authentication
4. **Return Anthropic-compatible response JSON** with `content`, `model`, `usage` fields

### Optional but Recommended

- `/v1/messages/count_tokens` support (proxy returns 501 if missing)
- Same error response format (`{"type": "error", "error": {"type": "...", "message": "..."}}`)
- Rate limit headers (`retry-after`) for automatic backoff

---

## Adding a New Provider

1. Verify the provider has an Anthropic-compatible endpoint
2. Add env vars to proxy `.env`:

```bash
# Example: adding a hypothetical provider for Opus tier
OPUS_PROVIDER_API_KEY=your_key_here
OPUS_PROVIDER_BASE_URL=https://api.example.com/anthropic
```

1. Set the model tier mapping:

```bash
ANTHROPIC_DEFAULT_OPUS_MODEL=example-model-name
```

1. Restart the proxy and test:

```bash
curl -s http://127.0.0.1:3000/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: any-value" \
  -H "anthropic-version: 2023-06-01" \
  -d '{"model": "example-model-name", "max_tokens": 100, "messages": [{"role": "user", "content": "Hello"}]}' \
  | python3 -m json.tool
```

1. Update this file with the provider's compatibility details.

---

## Known Incompatible Approaches

| Approach                | Why It Fails                                    |
| ----------------------- | ----------------------------------------------- |
| LiteLLM standalone      | No OAuth forwarding; forces API key billing     |
| Cloudflare Worker proxy | Adds network hop; may strip OAuth headers       |
| HTTPS_PROXY env var     | Cannot inspect request bodies for model routing |

See the [OAuth proxy research doc](../../../../../../../.claude/automation/claude-telegram-sync/docs/oauth-proxy-research.md) for a full evaluation of 11 approaches.
