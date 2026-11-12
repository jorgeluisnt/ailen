# Ailen

A free, open-source iPhone and iPad music player for local files, focused on
playback without an account, server or internet connection.

Ailen is based on [Aria](https://github.com/evince55/Aria) by evince55, used
under the MIT license (see [LICENSE](LICENSE)).

## Features

- **Local library:** import FLAC, ALAC, MP3, AAC, AIFF and WAV files from the Files app.
- **Equalizer:** 10-band parametric EQ, with presets and AutoEQ headphone profiles.
- **Playlists:** smart playlists, M3U import and export, and bulk folder import.
- **Offline library:** imported files, favorites and playlists stay on the device.
- **Source information:** the player shows codec, sample rate and bit depth
  when the file's audio track reports them. Unknown values stay unavailable.
- **Free:** every feature is included, with no purchases or subscription.

## Install

Ailen isn't on the App Store yet, so for now you build it yourself. You need:

- A Mac with [Xcode](https://apps.apple.com/app/xcode/id497799835) 26.5 or later
- An Apple ID, added in Xcode under **Settings → Accounts** (a free one works)
- An iPhone on iOS 16.6 or later

Then plug in and unlock your phone, and run:

```sh
git clone https://github.com/jorgeluisnt/ailen.git
cd ailen
make doctor    # tells you if anything is missing
make install
```

To try it in the simulator instead, with no Apple ID or phone, run `make sim`.

> **With a free Apple ID, the app stops opening after 7 days.** Plug in and run
> `make install` again to renew it. Your music and settings are kept. A paid Apple
> Developer account extends this to a year.

## Add your music

Open **Biblioteca**, tap **Importar** and choose your files. No server is needed.

The original Aria server code remains in the repository while the local
player is being migrated. It is hidden from the app's navigation.

## Develop

Run the iOS tests with `make test`. See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)
for architecture and setup, [docs/OFFLINE_MVP.md](docs/OFFLINE_MVP.md) for the
current audit and pending hardware checks, and [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)
for releases.

## License

[MIT](LICENSE)
