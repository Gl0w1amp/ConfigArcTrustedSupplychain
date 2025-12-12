# Minisign keys

This repository commits only the public Minisign key. Generate keys locally and keep the secret key private.

Commands (run from repo root):

```bash
minisign -G -W -p keys/cats.pub -s minisign.key
# Linux
base64 -w0 minisign.key
# macOS
base64 minisign.key
```

Use the base64 output as the `MINISIGN_SECRET_KEY_B64` secret in GitHub Actions. Do **not** commit `minisign.key`.
