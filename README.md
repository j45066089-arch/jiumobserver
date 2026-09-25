# JumioObserver — observe-only KYC diagnostic (Phase A)

Dumps the final images + metadata that PaysafeCard sends to Jumio, so
you can see exactly what reached the server (and whether the selfie is
mirrored or mis-rotated).

## Output
`<app container>/Documents/JumioObserver/`:
- `selfie_*.jpg` / `selfie_live_*.jpg` / `selfie_depth_*.jpg` — the face image(s)
- `uploadbody_*.jpg` / `uploadbody_*.bin` — bodies of requests to *.jumio.ai
- `meta_*.json` — width/height/**rotation**/format/iso per image
- `upload_*.json` — target URL, method, content-type, content-length
- `INJECTED.txt` — proves the tweak loaded

The `rotation` field in `meta_*.json` is the mirror/rotate hint: compare
a dumped selfie against your real face to settle the mirroring question
in seconds.

## Verify injection
1. Install the .deb, relaunch PaysafeCard.
2. Start a verification (ID scan + selfie), then cancel after the selfie.
3. Pull the folder: `scp -P 2222 root@127.0.0.1:<dumpdir>/* ./`
4. Open the `*.jpg` files.

No mutation of the app or its network traffic — observation only.
