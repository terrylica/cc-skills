← [Back to plugin CLAUDE.md](../CLAUDE.md)

# Stable local signing identity + TCC (2026-06-11)

Ad-hoc signing (`codesign --sign -`) mints a new code identity per build →
TCC (Bluetooth/mic/location) re-prompts after every reinstall. The Makefile
signs with the self-signed cert **"FloatingClock Local Signing"** when
present (auto-fallback to ad-hoc). One Allow then persists forever.
Recreate on a new machine (OpenSSL 3 p12 import is broken against macOS
`security` — import PEMs separately):

```bash
DIR=~/.local/share/floating-clock-signing && mkdir -p $DIR && cd $DIR
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 3650 -nodes \
  -subj "/CN=FloatingClock Local Signing" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false"
security import key.pem  -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign
security import cert.pem -k ~/Library/Keychains/login.keychain-db
security add-trusted-cert -p codeSign -k ~/Library/Keychains/login.keychain-db cert.pem  # GUI password dialog
```

Silent Bluetooth pre-authorization is impossible without MDM — the grant
row is `kTCCServiceBluetoothAlways` / `com.terryli.floating-clock` in the
user TCC.db; one human click is mandatory, once per identity.

**Identity-change gotcha**: switching identities (incl. the ad-hoc →
stable-cert migration) RESETS every TCC grant — Bluetooth, microphone, and
Location Services each need one re-Allow on the next use.
