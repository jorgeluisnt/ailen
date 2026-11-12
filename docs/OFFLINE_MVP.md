# Local-only MVP audit

## Current implementation

- `Managers/LocalLibraryManager.swift` imports from Files, copies into
  `Documents/AriaLibrary`, and persists library entries in
  `Documents/local_library.json`. `Services/FolderImporter.swift` handles
  folders. Imported files are not changed by the navigation work.
- `Managers/PlayerManager.swift` owns playback, queue, repeat, shuffle and
  interruption handling. `Services/AVPlayerPath.swift` plays local files
  through `AVPlayer`; `Services/AudioEQTap.swift` applies EQ when active.
  `Managers/EQController.swift` persists the ten bands and parametric preset.
- `Services/NowPlayingService.swift` owns lock-screen information and remote
  commands. `Views/Root/ContentView.swift` owns tabs and the mini player.
- `Views/Player/FullScreenPlayerView.swift` now displays only audio properties
  read from the source track's format description. Unknown values remain
  "No disponible". These are not output-route measurements.

## Risks and pending verification

- A recognized extension does not establish that every FLAC or ALAC profile
  is decodable. Corrupt or unsupported files still need device playback tests.
- `AVAudioSession.setPreferredSampleRate` is only a request and is no longer
  called. `AudioOutputMonitor` reports the port and the session's `sampleRate`
  (see below). No bit-perfect or output bit-depth claim is made.
- `PlayerManager` does not observe `mediaServicesWereResetNotification`.
  After a media-services reset the `AVPlayer` may need rebuilding; this is
  untested.
- EQ uses a real-time processing tap and changes the signal. The graphic
  EQ now applies an automatic preamp (see Phase 3). AutoEQ profiles keep the
  preamp written in the profile; it is not recomputed.
- Route changes and audio interruptions have handlers, but USB disconnect,
  Bluetooth handoff and gapless behavior need physical testing.
- `LocalLibraryManager.cleanupOrphans()` is no longer called automatically.
  It removes files missing from the JSON index and must be audited before
  reuse in any library migration.

## Output route (Phase 2)

`Services/AudioOutputMonitor.swift` publishes `AudioOutputSnapshot`: the
route's output ports (name and `AVAudioSession.Port`) and the session's
effective `sampleRate`. It is injected as an environment object and shown in
the full-screen player under the source line, e.g.
"Archivo: FLAC · 24 bits / 96 kHz" and "Salida: USB · <DAC> · 48 kHz".

- "DAC USB conectado" appears only when the primary output is `.usbAudio`.
  Bluetooth (A2DP/LE/HFP), wired headphones, AirPlay and CarPlay have their
  own labels.
- The rate is shown only after `NowPlayingService` activates the session
  (it posts `.ariaAudioSessionActivated`). It returns to "No disponible" on
  an interruption or a media-services reset until playback reactivates it,
  and when the route has no outputs.
- Refreshed on route change, interruption, media-services reset and app
  activation. The local path uses `AVPlayer`; there is no `AVAudioEngine`
  configuration-change notification to observe.
- The session rate is the rate the app's output runs at. It is not a
  measurement of the DAC's clock, and output bit depth is not exposed.
- `Tests/AudioOutputMonitorTests.swift` covers USB, Bluetooth, wired, no
  output, rate before activation, route change, interruption and reset with
  an injected session and notification center.

### Physical tests pending (iPhone + USB DAC)

None of these has been verified on hardware.

| Scenario | Expected |
|---|---|
| Connect USB DAC while playing | "DAC USB conectado", DAC name, rate shown |
| Disconnect USB DAC while playing | Playback pauses, output changes to speaker, no crash |
| 44.1 kHz and 96 kHz files on the DAC | Record the rate the session reports for each |
| Bluetooth headphones | Shown as Bluetooth, never as USB DAC |
| Lightning/USB-C 3.5 mm adapter | Record the reported port type (adapters can be `.usbAudio`) |
| Phone call during playback | Rate "No disponible" during the call, shown again after resume |
| No output (e.g. route unavailable) | "Salida: No disponible", no crash |

## Directo / Ecualizador (Phase 3)

- `EQController.isDirect` is persisted with the curve (`direct` is optional
  in the JSON, so older `eq_settings.json` files load as Ecualizador).
  Directo keeps bands and AutoEQ profile; `isEnabled` is now derived:
  not Directo and a non-flat or parametric curve.
- `PlayerManager.setAudioMode(direct:)` bypasses or re-engages the existing
  tap in place: no item rebuild, so position and queue are kept. New items in
  Directo get no tap at all (unless pitch is changed). Choosing an AutoEQ
  profile leaves Directo.
- Fixed: graphic band updates were pushed over an active parametric curve,
  overwriting its gains. They are now skipped while a profile is active.
- Headroom: `Models/EQHeadroom.swift` sums RBJ peaking responses (cascaded
  filters add in dB) and sets AUNBandEQ's global gain to `-peak`. Measured
  on macOS through the real AUNBandEQ at 48 kHz: the model is within 0.1 dB
  of the measured peak and never below it; with the preamp, measured peaks
  are −0.10 to 0.00 dB (single +12 band, two adjacent +12, all +12, V curve,
  alternating ±6). All bands at +12 peak at 14.1 dB, above the largest band.
  The preamp lowers overall loudness; switching Directo ↔ EQ can therefore
  change perceived volume.
- `EqualizerView` shows the selector, explains that the EQ modifies audio and
  that Directo is not guaranteed bit-perfect, and shows the preamp. The full
  player shows "Modo: Directo (sin EQ)" or "Modo: Ecualizador".
- A local file that AVPlayer cannot open now shows a Spanish message instead
  of AVFoundation's generic text.
- Not done: editable band frequency and Q for the graphic EQ (only AutoEQ
  profiles carry Q), and a user-set preamp.
- Tests: `Tests/AudioModeTests.swift` (mode transitions, persistence, old
  settings, headroom reference values, corrupt local file). The non-UI checks
  were also run on macOS against the same sources and passed.

## Design, accessibility and scale (Phase 4)

- All visible UI text is Spanish, except the hidden Search view and error
  text from hidden streaming services. Persisted raw values were not
  changed; `displayName` properties carry the Spanish text (EQ presets,
  sleep timer, playlist sort and tabs, library tabs). The fallback artist
  "This Device" stays because it is stored in library data.
- Large libraries: rows of an ungrouped library sat in one non-lazy
  `VStack`, so every row was built at once. `LibrarySectionView` now returns a
  `Section`, so the parent `LazyVStack` builds rows on demand. Sorting
  (measured ~75 ms for 20k titles on this Mac) now only reruns when the
  tracks or the order change; search filters the sorted list 150 ms after
  typing stops, and matches title, artist or album, ignoring accents.
- Full player: content is capped at 560 pt wide; artwork is 420 pt on iPad
  (regular width), 290 pt on iPhone and 160 pt at accessibility text sizes so
  controls still fit. Artwork is hidden from VoiceOver; section headers are
  marked as headers.
- Offline: no network request runs at launch. The backend is unset, library
  sync is never configured and the search tab is hidden. The AutoEQ catalogue
  is downloaded from GitHub only when the user opens it; importing a profile
  from a file works offline.
- `make check` compiles app and tests without a simulator runtime.
- Not done: a dedicated iPad layout (split view, landscape), and a VoiceOver
  and Dynamic Type pass on a device.

## Validation on this machine

- Xcode 27.2 (27B52) with the iOS 27.2 SDK. No iOS simulator runtime is
  installed (`xcrun simctl list runtimes` is empty), so `make sim` and
  `make test` cannot run. iPhone playback, USB DAC behavior and running the
  XCTest suite remain pending.
- `xcodebuild build-for-testing` (after Phase 2 as well) for `generic/platform=iOS Simulator`
  (`CODE_SIGNING_ALLOWED=NO`) succeeds: app and test targets compile.
- `SourceAudioInfo.inspect` was run on macOS against generated files.
  Results: WAV 16/44.1 and 24/96, AIFF 24/96, ALAC 16/44.1 and 24/96,
  FLAC 16/44.1, 24/96 and 24/192 report the correct codec, bits and rate;
  MP3 and AAC report the rate and "No disponible" for bits. FLAC and ALAC
  set `mBitsPerChannel = 0`; their bit depth is read from `mFormatFlags`.
  The same check on iOS hardware is pending.
