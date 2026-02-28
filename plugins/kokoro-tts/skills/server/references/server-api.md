# Kokoro TTS Server API Reference

OpenAI-compatible HTTP API at `http://127.0.0.1:8779`.

## Endpoints

### GET /health

Returns server status.

```json
{
  "status": "ok",
  "provider": "kokoro-tts-mlx",
  "model": "mlx-community/Kokoro-82M-bf16",
  "device": "mlx-metal",
  "default_voice": "af_heart",
  "default_lang": "en-us"
}
```

### GET /v1/models

Returns available models.

```json
{
  "object": "list",
  "data": [{ "id": "kokoro-82m", "object": "model", "owned_by": "kokoro" }]
}
```

### POST /v1/audio/speech

Synthesize text to audio.

**Request body**:

```json
{
  "input": "Hello world",
  "voice": "af_heart",
  "language": "en-us",
  "speed": 1.0,
  "response_format": "wav"
}
```

**Parameters**:

| Field             | Type   | Default    | Description                        |
| ----------------- | ------ | ---------- | ---------------------------------- |
| `input`           | string | (required) | Text to synthesize                 |
| `voice`           | string | `af_heart` | Voice name                         |
| `language`        | string | `en-us`    | Language code                      |
| `speed`           | float  | `1.0`      | Speech speed multiplier (0.1–5.0)  |
| `response_format` | string | `wav`      | Output format: wav, mp3, opus, pcm |

**Response**: Audio bytes with appropriate `Content-Type` header.

**Response headers**:

| Header          | Example     | Description          |
| --------------- | ----------- | -------------------- |
| `Content-Type`  | `audio/wav` | Audio MIME type      |
| `X-Voice`       | `af_heart`  | Voice used           |
| `X-Duration-Ms` | `1234`      | Total synthesis time |

**Format support** (requires `ffmpeg` for mp3/opus):

| Format | Content-Type | Requires ffmpeg |
| ------ | ------------ | --------------- |
| wav    | audio/wav    | No              |
| mp3    | audio/mpeg   | Yes             |
| opus   | audio/opus   | Yes             |
| pcm    | audio/pcm    | No (raw int16)  |

## Usage Examples

```bash
# Synthesize WAV
curl -X POST http://127.0.0.1:8779/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{"input": "Hello world", "voice": "af_heart"}' \
  -o output.wav

# Synthesize MP3
curl -X POST http://127.0.0.1:8779/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{"input": "Hello world", "response_format": "mp3"}' \
  -o output.mp3
```
