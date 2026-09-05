# SoundPuddle

Lokales **Schwarm**-Audio: mehrere iPhones bilden ein Lautsprecherfeld um den Tisch — ohne Internet.

**Version 0.0.3**

## Magic Moment

1. Host öffnet die App, wählt einen Song, tippt **Schwarm starten**
2. Andere ziehen das Schwarm-Icon zur Mitte (Nahbereich ~2 m)
3. Nah-Ultraschall-Chirp kalibriert Positionen am Tisch
4. Jedes Gerät spielt seinen räumlichen Anteil (L / R / Mitte)
5. Beat-Lichtshow, demokratische Playlist-Votes, Drop-in/out mit Feld-Rebalance

## LiveContainer

1. Local Network / Mikrofon / Bluetooth in der **LiveContainer-Host-App** erlauben
2. Fix File Picker für Song-Import
3. Soft-Encryption ist in LiveContainer automatisch aktiv

## Build

```bash
xcodegen generate
xcodebuild -scheme SoundPuddle -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

Unsigned IPA: GitHub Actions Artifact am Branch `dskjasoundpuddle-61ba`.
