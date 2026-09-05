# SoundPuddle

Temporäre Silent-Discos auf dem iPhone: ein Host streamt Audio lokal an alle Peers im Raum — **ohne Internet**, über Multipeer Connectivity (Wi‑Fi P2P + Bluetooth).

> Ein Pfützchen Klang im Raum — betreten, hören, wieder auflösen.

## Use Cases

- Spontane Silent-Party im Park
- Geführte Stadttour ohne Headset-Miete
- Gemeinsamer Filmton im Zug (importierte Audiospur)

## Architektur (v1)

- **Topologie:** Host-Stern (kein Peer-Relay)
- **Transport:** `MultipeerConnectivity` (`soundpuddle`), Encryption required
- **Audio:** PCM 16-bit LE mono 24 kHz, ~20 ms Frames, unreliable send
- **Control:** reliable Messages (hello/welcome/streamStart/stop/roster/ping/goodbye/reject)
- **Playback:** Jitter-Buffer (3–4 Frames je Modus)

Apple exponiert kein klassisches Wi‑Fi Direct; Multipeer Connectivity ist der native Weg für raum-lokales Mesh ohne Infrastruktur.

## Limits

- Max. **7 Joiner** (+ Host) — Soft-Warnung ab 6
- Kein System-Audio-Capture (Cinema = importierte Datei)
- Unsigned IPA nur via Sideload (AltStore / TrollStore / eigene Signing-Tools)

## Lokal bauen

```bash
brew install xcodegen
xcodegen generate
open SoundPuddle.xcodeproj
```

Xcode 16+, iOS 17+, physisches iPhone für Mesh-Tests.

## CI — unsigned IPA

Workflow: [`.github/workflows/build-unsigned-ipa.yml`](.github/workflows/build-unsigned-ipa.yml)

- Runner: `macos-15`
- `xcodegen` → `xcodebuild` Release `iphoneos` mit Signing deaktiviert
- Packt `Payload/SoundPuddle.app` → Artifact **`SoundPuddle-unsigned.ipa`**
- Keine Certificates, kein `exportArchive`, kein TestFlight

Trigger: Push auf `main` / `dskja*`, oder `workflow_dispatch`.

## Permissions

- Lokales Netzwerk / Bonjour `_soundpuddle._tcp`
- Bluetooth (Fallback)
- Mikrofon (nur Host)

## Lizenz

MIT — siehe [LICENSE](LICENSE). Fonts: Syne & IBM Plex (OFL) — [LICENSE-THIRD-PARTY.md](LICENSE-THIRD-PARTY.md).
