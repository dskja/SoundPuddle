# SoundPuddle

Temporäre Silent-Discos: lokales Audio-Mesh ohne Internet (Wi‑Fi P2P + Bluetooth / MultipeerConnectivity).

## Features

- Host/Join Silent-Disco Sessions im selben Raum
- Mikrofon- oder Datei-Quelle (PCM 16-bit mono 24 kHz)
- Jitter-Buffer, Link-Qualität, Display-Name
- LiveContainer-Anpassungen (weiche Encryption, UX-Tips, sandboxed File-Import)

## LiveContainer

SoundPuddle läuft als Guest-App in [LiveContainer](https://github.com/LiveContainer/LiveContainer):

1. **Berechtigungen** für Lokales Netzwerk, Mikrofon und Bluetooth in der **LiveContainer-Host-App** erteilen (nicht nur in SoundPuddle).
2. Für Audio-Dateien **Fix File Picker** in LiveContainer aktivieren.
3. **Multitask-Modus vermeiden** — VoIP/Mikrofon-Audio bricht dort oft ab; SoundPuddle als primäre Guest-App nutzen.
4. Soft-Multipeer-Encryption ist in LiveContainer automatisch aktiv.

Unsigned IPA: GitHub Actions Artifact `SoundPuddle-unsigned-ipa` am Branch `dskjasoundpuddle-61ba`.

## Build

```bash
# Fonts werden in CI geladen; lokal analog project.yml / workflow
xcodegen generate
xcodebuild -scheme SoundPuddle -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

## Version

1.1.0 — LiveContainer-Support, Bugfixes, Stabilitäts- und UX-Polishes.
