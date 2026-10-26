# Reel — round 6 builders: the user interface for round 5

Read `build/BRIEF.md` (rules; Tessel docs only from `build/tessel-docs/`,
especially `ui_*.md` and `reference_views.md`/`reference_modifiers.md`),
then `build/ROUND5.md` (the clean-room rule still applies: don't read
VLC's, mpv's or other GPL code — design the UI yourself).

Round 5 built engine modules with tests: `fx/` (audio effects), `vfx/` +
`render/` (video filters and picture settings: `render.View`,
`vfx.Settings`), `library/` (playlists, SQLite library, history, per-file
settings, episodes, bookmarks, keymap, `Preferences`), `subs/` (styling,
encodings, OpenSubtitles, dialogue search/transcript, siblings), `export/`
(MKV/MP4 clips, GIF), `disc/` (DVD/Blu-ray titles). Each module's files and
its builder's notes say how it's used; read the module you build UI for.

You build **views**, not the app: the lead owns `main.tsl`, `player.tsl`,
`info.tsl` and `play/` and wires your views in afterwards. Put your views
in the shared module `ui/` (import it as `import "../ui"` from tests; the
app imports `"ui"`), in your own files only, with a name prefix per
builder for private helpers. `ui/icons.tsl` (the lead's) has the app's
icon buttons (`SvgButton`, `IconButton`) and Lucide SVG icons — use them
and add your own icons in your files the same way. Since the module is
shared, **keep your files compiling at all times** (draft elsewhere,
`tessel check ui` before saving into `ui/`; `tessel check` on a module
folder prints a known false "no entry point" error — look for other
errors). Everything takes plain values, `bind` parameters and callbacks
(`fn()`, `fn(String)` …) — no global state, no file or network access
inside views unless your section says so.

Look: the player window is dark (`.rgb(31,31,31)` bars, `.rgb(23,23,23)`
panels, accent orange `.rgb(242,140,26)`, text `.rgb(217,217,217)`; see
`main.tsl`). Separate windows (Effects, Library, Preferences, dialogs) use
the system colours (`.primary`, `.secondary`, default backgrounds) so they
follow light/dark mode, with the orange accent for selection. Every
control needs an accessibility label or visible text; keyboard reachable.

**Verify headless only**: write a demo app per area under
`build/scratch/<you>/demo/` (its own folder, `app … { … }` using your
views with sample data), build it with `tessel build`, and drive it with
`TESSEL_SCRIPT` (`click`, `type`, `snapshot`, `dump` — see
`ui_testing.md`); look at the snapshots. Never open a real window. Also a
`tests/ui_<area>/main.tsl` (`fn main()`, prints `ui_<area>: N of M
passed`) for the pure helper functions you write (formatting, parsing,
validation, layout maths). Never touch the user's real Reel data folder.
Author/date headers (`// Date: 2026-10-26`), no git, no loose pkill.

---

## ui-fx: "Effects and Filters" — files `ui/fx_*.tsl`, test `tests/ui_fx`

One window content view with tabs (`EffectsView`), each tab also usable
alone:
- **Equalizer** (`fx.Settings`): on/off, preset picker (`fx.presets()`),
  preamp, 10 vertical band sliders with dB labels and frequency labels, a
  drawn response curve (Canvas) of the current settings, reset.
- **Loudness & dynamics**: normalisation mode and target LUFS, max boost;
  compressor (threshold, ratio, knee, attack, release, makeup) with a
  drawn transfer curve; limiter ceiling; a live meter readout (M/S/I LUFS,
  LRA, true peak, current gain, gain reduction) from values passed in.
- **Stereo**: mode, width, balance, crossfeed on/amount.
- **Video** (`render.View` + `vfx.Settings`): brightness, contrast,
  saturation, hue, gamma sliders with reset; crop (four edges, "detect
  black bars" switch); aspect ratio picker (`render.aspectPresets` +
  custom); zoom and pan; flip H/V; rotate 90/180/270; deinterlace mode,
  double rate, auto; sharpen and denoise.
- **Synchronisation**: audio delay, subtitle delay, secondary subtitle
  delay (± ms steppers + text fields), playback speed.
- Each change calls `onChange()` (the app debounces). Signature sketch:
  `EffectsView(audio: bind fx.Settings, look: bind render.View, filters:
  bind vfx.Settings, sync: bind ui.SyncSettings, meter: ui.MeterReadout,
  tab: bind String, onChange: fn())` — define `SyncSettings` and
  `MeterReadout` as plain structs in your files.

## ui-library: library, home screen, previews — files `ui/lib_*.tsl`, test `tests/ui_library`

- **Library window** (`LibraryView`): sidebar groups (Movies, TV Shows,
  Music, Other, History, Playlists) with counts; search field; sort
  picker; a grid of posters (thumbnails passed in as pixel lists, a
  placeholder icon otherwise) or a list; TV shows → seasons → episodes
  with watched marks and progress bars; Music → artists → albums → tracks;
  context menus (Play, Play next, Add to playlist, Show in Finder via a
  callback, Forget, Mark watched/unwatched). Data comes from
  `library.Library` methods: the view may take `lib: bind library.Library`
  and call its query methods (they're SQLite reads on the UI thread), or
  you may introduce a small model struct that caches query results —
  your choice; keep scrolling smooth for 5,000 items (`LazyVStack`).
- **Home / start screen** (`HomeView`) shown in the player window when
  nothing plays (replaces the current "Reel / Drop a video…" canvas text):
  "Continue watching" row (thumbnail, title, progress bar, time left),
  "Next episode" suggestions, recently added, buttons Open File / Open
  Folder / Open Network Stream / Library. Dark player look.
- **Playlist panel v2** (`PlaylistPanel`): replaces the one in `main.tsl`
  (look at it): rows with title/duration, current item marked, drag to
  reorder (`ui_lists.md`), remove, Add, Clear, Save playlist (callback),
  Shuffle/Repeat shown.
- **Seek preview** (`SeekPreview`): the floating thumbnail with time above
  the seek bar while hovering (pixels + time passed in, position x), and a
  **scene strip** (`SceneStrip`): a horizontal row of scene thumbnails
  with times; clicking one calls `onSeek(t)`; current scene highlighted.
- **Chapters menu helper** and **bookmarks list** (`BookmarksPanel`: list
  with rename/delete/jump, add at current time).

## ui-prefs: Preferences — files `ui/prefs_*.tsl`, test `tests/ui_prefs`

`PreferencesView(prefs: bind library.Preferences, keymap: bind
library.Keymap, tab: bind String, onChange: fn(), onAddFolder: fn(),
onRescan: fn(), …)` with tabs:
- **General**: resume (ask/always/never), remember settings per file,
  auto-play next episode, recent count, clear history (with a confirm
  step inside the view), language of the UI is English only (no setting).
- **Playback**: jump sizes, speed step, end of playlist behaviour, sleep
  timer default, mini player on/off behaviour, always-show controls.
- **Audio**: preferred audio languages (ordered list editor), default
  normalisation, default EQ preset, output volume limit.
- **Video**: deinterlace default, default aspect, snapshot folder and
  format.
- **Subtitles**: preferred languages, subtitle mode (auto/forced only/
  always/off), default encoding (`subs.encodingList` + titles), style
  editor for `subs.TextStyle` (primary and secondary) with a live preview
  drawn by `subs.drawTracks` on a Canvas over a sample frame.
- **Library**: folders list (add via callback, remove), scan on start,
  rescan button, thumbnail cache size and clear.
- **Network**: cache seconds, max quality, user agent.
- **OpenSubtitles**: API key field (secure), username, a "Get a key"
  link to opensubtitles.com, status text passed in.
- **Shortcuts**: every `library.keyActions` row with its combos
  (`displayCombo`), click to record a new combo (capture with
  `.onKeyEvent`), remove, conflicts shown inline (`keymap.conflicts()`),
  reset one / reset all.

## ui-tools: dialogs and panels — files `ui/tools_*.tsl`, test `tests/ui_tools`

- **Find in dialogue** (`FindPanel`): search field, source picker (all /
  each subtitle track), results with time, highlighted match, context
  lines; Enter/arrow keys move through results; `onSeek(t)`.
- **Transcript** (`TranscriptPanel`): lines of one source with times,
  current line highlighted and kept in view (`scrollTo`), click to seek.
- **OpenSubtitles** (`SubtitleSearchView`): query (title, season, episode,
  languages), results table (title, release, language, downloads, hash
  match badge, hearing-impaired/forced/AI flags), Download button, login
  sheet (username/password, secure field) when a download needs it, error
  and quota text — all through callbacks; uses `subs.OsSubtitle` values.
- **Text encoding chooser** (`EncodingPicker`): list grouped by script
  with the detected one marked and its confidence.
- **Export clip** (`ExportClipView`): A and B times (editable, "set from
  current position" buttons), duration, track checkboxes (from
  `core.Media` tracks), container MKV/MP4 (MP4 greyed for tracks it can't
  carry — `export.payloadMode` tells), exact start toggle, output path
  (choose via callback), Export; progress/result text passed in.
- **Export GIF** (`ExportGifView`): range, width, fps, dither, loop,
  estimated size, preview of the first frame (pixels passed in).
- **Disc titles** (`DiscTitlesView`): titles of a `disc.Disc` with
  duration, chapters, angles, audio/subtitle languages, main feature
  marked; angle picker; Play.
- **Jump to time** (`JumpToTimeView`): h:m:s field with parsing
  (`1:23:45`, `83:45`, `45s`, `+30`, `-1:00`), Enter jumps.
- **Sleep timer** (`SleepTimerView`): off, 15/30/45/60/90 min, end of
  current item, custom; shows time left.
- **Media information v2** (`MediaInfoView`): tabs General/Codec/Metadata/
  Statistics/Chapters, from `core.Media`, the decoders' `streamInfo`
  strings (each module has `streamInfo(track)`; the lead passes them in),
  and live statistics values passed in; copy-to-clipboard button.

## Report

When done, reply with: the views and their full signatures, what each
callback means, demo snapshots you looked at, tests, known gaps, and the
exact steps for the lead to wire them into `main.tsl`.
