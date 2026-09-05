# SoundPuddle

Lokale Silent-Disco Sessions über MultipeerConnectivity — ohne Internet.

**Version 0.0.2**

## Neu in 0.0.2

- Liquid-Glass UI (Polyfill für iOS 17+, optisch an iOS 26 angelehnt)
- Host: Pause/Resume, Monitor-Mute für Datei-Preview
- Join: Lautstärke + Mute, Roster, RTT-Anzeige, Session-Timer
- Stabilität: File-Capture Realtime-Rate, Idle-Timer-Idempotenz, Handshake-Timeout bis Live,
  Ping/Pong unicast, stabile Peer-IDs, Stereo-Downmix, Jitter Wrap-Around,
  Audio-Interruption Recovery, LiveContainer-Härtung

## LiveContainer

1. Local Network / Mikrofon / Bluetooth in der **LiveContainer-Host-App** erlauben
2. Fix File Picker aktivieren (Datei-Import)
3. Kein Multitask-Modus für Mic/VoIP-Audio
4. Soft-Encryption ist in LiveContainer automatisch aktiv

## Build

```bash
xcodegen generate
xcodebuild -scheme SoundPuddle -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

Unsigned IPA: GitHub Actions Artifact am Branch `dskjasoundpuddle-61ba`.
