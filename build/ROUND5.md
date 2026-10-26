# Reel — round 5 builders: beyond VLC

Read `build/BRIEF.md` first: every rule there applies (Tessel docs only from
`build/tessel-docs/`, own files only, author/date headers (`// Date:
2026-10-26` for new files), tests ending `<name>: N of M passed`, Tessel
problems to `build/TESSEL_ISSUES.md`, contract requests to `build/NEEDED.md`,
no git, no loose pkill, never open GUI windows, never run bare `tessel`).
`build/TESSEL_ISSUES.md` lists speed traps (module-level `let` lists are slow
to read, re-passing `bind` parameters is slow, building big lists is slow —
reuse buffers).

## The clean-room rule (new, strict)

Reel will be released, and code translated from GPL/LGPL programs would
bind it to their licences. So, for everyone this round:

- **Never read the source code of FFmpeg/libav, VLC, mpv, MPlayer,
  GStreamer, libass, libdvdread/libdvdnav, libbluray, or any other GPL/LGPL
  project**, and don't open the FFmpeg source copies under `build/scratch/*/ffsrc`.
- Work from specifications, RFCs, standards, published papers and plain
  descriptions (Wikipedia, format documentation, blog posts that describe
  without copying code). Permissively licensed references (MIT/BSD/ISC,
  public domain) may be read, but write your own code and say in the file
  header what you followed.
- ffmpeg/ffprobe/python may still be **run** as black-box oracles for test
  references, as before.
- Data tables that are part of a standard are fine; preset values or tables
  that only exist in GPL code (e.g. VLC's equalizer presets) are not —
  design your own.

## Context

The player app (`main.tsl`, `player.tsl`, `info.tsl`, `play/`) is the
lead's: you build engine modules with clean public APIs and tests; the
lead wires them into the UI afterwards. If a module needs UI, you may add
`public view`s inside your own module (they must work headless and be
driven by plain values and callbacks), plus a small demo in your test.
Tessel limits that shape the work: whole-file reads only
(`readData`, no ranged local reads — Tessel issue #45); HTTP(S) via
`request`/`fetch`/`download` (Range headers work over HTTP; `request`
returns the whole body); WebSocket client; SQLite via `openDatabase`; no
TCP/UDP sockets, no server. `background` jobs can't call `request` (do
network calls from the caller's thread and pass bytes to jobs).
`core.Picture` now has `interlaced` and `topFieldFirst`.

---

## net: modules `net/` and `xml/` — tests `tests/net`, `tests/xml`

Only touch `net/`, `xml/`, their tests, `build/scratch/net/`.

1. **`xml/` first** (others need it — have it working within your first
   steps and say so in `build/NEEDED.md`'s top line "xml/ ready"): a small
   non-validating XML 1.0 parser → `xml.Node` tree (name, attributes in
   order, children, text), entities (predefined + numeric), CDATA,
   comments/PIs skipped, namespaces kept as prefixes, `xml.parse(text) ->
   Result<Node>`, helpers `child(name)`, `children(name)`, `attr(name)`,
   `text`; and a writer `xml.Node.toText(indent:)`.
2. **HTTP access** for the player: `net.Remote` helpers usable from app
   code: probe (size, type, ranges supported, redirects resolved, with a
   HEAD or `Range: bytes=0-0`), ranged reads with a block cache, retries,
   errors as values.
3. **HLS** (RFC 8216 + later HLS spec items): master and media playlists,
   variants (bandwidth, resolution, codecs), `EXT-X-MEDIA` alternative
   audio/subtitle renditions, segments with durations, byte ranges,
   `EXT-X-KEY` AES-128 (write AES-128-CBC yourself, FIPS-197; check with
   `openssl`/python), `EXT-X-MAP` (fMP4 init), discontinuities, live
   playlists (reload timing, sliding window), `EXT-X-PROGRAM-DATE-TIME`
   kept. Variant choice from measured throughput (an ABR rule you design,
   switching only at segment boundaries).
4. **DASH** (ISO/IEC 23009-1): static and dynamic MPDs, periods,
   adaptation sets, representations, `BaseURL` resolution, `SegmentTemplate`
   (`$Number$`, `$Time$`, `$Bandwidth$`, `$RepresentationID$`, widths like
   `%05d`) with and without `SegmentTimeline`, `SegmentList`,
   `SegmentBase` + `sidx` (parse the box), init segments.
5. **Segments to packets**: turn TS segments (via `demux`'s TS parser on the
   segment bytes) and fMP4 init+fragment pairs (via `demux` MP4) into packets
   on one continuous timeline, with a `net.StreamBuffer` that appends
   segments into one growing byte store + `core.Media` (packet offsets into
   it), can drop old segments (rebasing offsets) and reports buffered
   seconds — the player will treat it as its `file` + `media`.
6. **Internet radio**: Icecast/SHOUTcast — find out whether Tessel can
   read an endless HTTP response as it arrives (`download` to a file while
   reading it? `request` with ranges?). If it can't, write the minimal
   repro into `build/TESSEL_ISSUES.md`, and support what works (e.g.
   radio given as HLS). ICY metadata (`StreamTitle`) parsing either way.
7. **Podcasts**: RSS 2.0 (+ iTunes tags) and Atom feeds → show title,
   image, episodes (title, date, enclosure URL/type/length, duration,
   description text).
- Tests: make HLS/DASH fixtures with ffmpeg (`-f hls`, `-hls_key_info_file`,
  fMP4 HLS, `-f dash`, live-style playlists) and read them through
  `file://` with `fetch`; ranged-HTTP checks may use a `python3 -m
  http.server` you start and stop yourself (by PID) in a script — keep
  `tests/net` itself runnable without a server.

## fx: module `fx/` — test `tests/fx`

Only touch `fx/`, `tests/fx/`, `build/scratch/fx/`.

Audio effects on the player's output (`core.Samples`, interleaved Float,
48 kHz stereo after the mixer, but any rate/channels must work), all
streaming with state kept between calls, settings changeable between
calls without clicks (smooth parameter changes):
- **Equalizer**: 10 bands (31 Hz … 16 kHz octaves), ±12 dB, preamp, peaking
  biquads designed from the Audio EQ Cookbook (RBJ) formulas; your own
  set of presets with the usual names (Flat, Classical, Club, Dance, Bass
  boost, Treble boost, Bass and treble, Headphones, Large hall, Live,
  Party, Pop, Reggae, Rock, Ska, Soft, Soft rock, Techno, Vocal) — values
  you choose.
- **Loudness**: an ITU-R BS.1770-4 / EBU R128 meter (K-weighting,
  momentary/short-term/integrated with gating, true-peak by 4×
  oversampling), and normalisation: target LUFS, gain from the measured
  loudness (so far, and from a pre-scan when the player gives one), with a
  look-ahead limiter so nothing clips; ReplayGain tags (track/album gain
  and peak from `media.tags`) as an alternative source.
- **Dynamics**: compressor (threshold, ratio, knee, attack, release,
  makeup), limiter.
- **Stereo**: modes stereo/mono/swap/left/right/mid-side width, a
  headphone crossfeed (your design, e.g. after the Bauer idea), balance.
- **Spectrum/visualiser data**: N log-spaced band levels and a short
  waveform for a view, cheap enough to run per chunk.
- `fx.Chain` holding all settings (a plain struct the player saves as
  JSON) with `process(_ s: core.Samples) -> core.Samples`, `reset()`, and
  `latency` (frames). Speed: print × real time for the full chain at
  48 kHz stereo (goal ≥ 200×). Tests: numeric — filter responses vs the
  designed curves, R128 against the EBU Tech 3341/3342 test signals (make
  them with python), limiter never exceeds its ceiling, no clicks on
  parameter changes.

## vfx: module `vfx/` and `render/` — tests `tests/vfx`, `tests/render`

Only touch `vfx/`, `render/`, `tests/vfx/`, `tests/render/` (keep its
checks passing), `build/scratch/vfx/`.

1. **Picture adjustments in `render`**: brightness, contrast, saturation,
   hue, gamma folded into the conversion tables (no extra pass); crop
   (pixels per edge, or detect black bars: write `vfx.detectCrop`), aspect
   ratio override (16:9, 4:3, 2.35:1, 1:1, custom), zoom/pan, flips; keep
   rotation. A `render.View` (or similar) settings struct the Converter
   (`play/video.tsl`, the lead's) passes through.
2. **Deinterlacing in `vfx`** on `core.Picture` (8–12 bit, all chroma
   forms): weave (off), bob (line doubling, both fields → double rate),
   linear blend, and a motion-adaptive deinterlacer of your own design
   (spatial edge-directed interpolation where there's motion, temporal
   where static — a well-known idea, but write it from descriptions only),
   single and double rate; auto mode by `Picture.interlaced`. ≤ 10 ms per
   1080i picture.
3. **Filters**: sharpen (unsharp mask), denoise (a spatio-temporal filter
   of your design), both ≤ 10 ms at 1080p.
4. **Scene detection**: a fast scene-change score per picture (from a small
   luma thumbnail) and `vfx.sceneCuts` for automatic chapters.
5. **Thumbnails**: `vfx.thumbnail(pic, width:)` → small RGBA pixel list
   (fast area-average downscale + colour conversion), for seek previews,
   the library and the scene strip; ≤ 3 ms from a 1080p picture.
- Tests: compare with ffmpeg's filters where they're comparable
  (`-vf eq`, `hue`, `crop`, `hflip`, `transpose`) within a small tolerance,
  deinterlacing PSNR vs the progressive source on synthetic interlaced
  clips you make (`-vf interlace`/`tinterlace`), speed lines.

## library: module `library/` — test `tests/library`

Only touch `library/`, `tests/library/`, `build/scratch/library/`.

- **Playlists**: read and write M3U/M3U8 (#EXTM3U, #EXTINF, #EXTVLCOPT
  ignored), PLS, XSPF (use `xml/` from the net builder when it's ready —
  until then work on the rest), WPL, CUE sheets (tracks as chapters of one
  file); relative paths and URLs; encodings (UTF-8, Latin-1 fallback).
- **Media library** in SQLite (`openDatabase`): folders to watch, a scan
  that lists media files (by extension and a quick sniff of the first
  bytes — never read whole big files during a scan; Tessel can only read
  whole files, so take name, size, dates, and fill duration/tags/codec
  lazily when the player reports them after playing, and fully for audio
  files under ~50 MB), search (title, artist, album, file name;
  accent/case-insensitive), sorting, groups (Movies, TV shows by series and
  season, Music by artist/album, Other), rescans that notice removed and
  changed files.
- **History and per-file memory**: position, finished flag, last played,
  play count, chosen audio/subtitle track (by language+codec, not index),
  volume, speed, audio/subtitle delays, crop/aspect/zoom, deinterlace,
  equalizer preset — `library.FileSettings` stored per file (keyed by path
  plus size, so moved files can be found again by name+size).
- **Episodes**: parse SxxEyy, 1x02, "Episode 2", date-based names, anime
  `- 07`; series name normalisation; "next episode" in a folder or the
  library; natural sort ("Ep 2" before "Ep 10").
- **Bookmarks** (named times per file) and **A-B loop** points stored per
  file.
- **Shortcuts**: a keymap model (action ids → key combos like
  `cmd+shift+s`), defaults matching Reel's current keys (read `main.tsl`'s
  `key()` and menus), conflict detection, parse/format for display.
- **Preferences**: one `library.Preferences` struct with every setting the
  app needs (folders, resume behaviour, subtitles style/encoding/languages
  preferred, audio language preferred, normalisation target, deinterlace
  default, network cache seconds, OpenSubtitles API key, theme…), JSON
  load/save with defaults for missing fields.
- **Thumbnail cache**: file layout and size cap (pictures come from the
  player).

## subs: module `subs/` — test `tests/subs`

Only touch `subs/`, `tests/subs/` (keep all existing checks passing),
`build/scratch/subs/`.

- **Styling** for text subtitles (SRT, WebVTT, tx3g, plain): font scale,
  colour, outline width/colour, shadow, background box and opacity, bold,
  vertical margin, position top/bottom (for a **secondary subtitle
  track** drawn at the top while the first is at the bottom), "override
  ASS styles" switch; `subs.draw` keeps its current default look.
- **Text encodings**: detect and decode UTF-8 (with/without BOM), UTF-16
  LE/BE, Windows-1250…1258, ISO-8859-1…16, KOI8-R/U, and the CJK encodings
  Shift_JIS, EUC-JP, GBK/GB18030, Big5, EUC-KR (mapping tables generated
  from the Unicode Consortium's mapping files or WHATWG encoding index
  files — both permissively available), with a confidence score; manual
  override.
- **OpenSubtitles** (REST API v1, api.opensubtitles.com): the movie hash
  (file size + sums of the first and last 64 KB — compute from `Data`),
  search by hash, by name/season/episode and language, download links
  (needs the user's API key and login token; build request/response
  handling as pure functions plus thin `request` calls; mock responses in
  tests — no live calls in `tests/subs`).
- **Find in dialogue**: an index over all text cues of all subtitle tracks
  of a file (and loaded subtitle files), case/accent-insensitive search
  with phrase matching, results with times and context; **transcript**
  model: the lines around a time for a scrolling transcript panel.
- Matching subtitle files beside a video (name variants, language codes in
  names like `.en.srt`, `.eng.forced.srt`), already partly in the app —
  move that logic here as `subs.siblingFiles(videoPath, folderListing)`.

## export: module `export/` — test `tests/export`

Only touch `export/`, `tests/export/`, `build/scratch/export/`.

- **Matroska writer** (RFC 9559 / Matroska spec): EBML header, Segment
  with SeekHead, Info (duration, title), Tracks (CodecID + CodecPrivate
  built from `core.Track.extra` for every codec Reel knows — the inverse of
  `demux/mkv.tsl`'s mapping), Clusters with SimpleBlocks (keyframe flags),
  Cues, Chapters, Tags; also writes subtitles (SRT/ASS/WebVTT/PGS) and
  attachments (fonts).
- **MP4 writer** (ISO/IEC 14496-12/14/15): ftyp, moov (mvhd, trak with
  tkhd, mdia, stbl with stsd from `extra` for h264/hevc/av1/vp9/aac/ac3/
  eac3/opus/flac/mp3, stts, ctts, stss, stsc, stsz, co64), mdat, edit
  lists for start offsets; faststart (moov first).
- **Lossless clips**: `export.planClip(media, track choices, from:, to:)` →
  packets to copy: video from the keyframe at/before `from` (and, as an
  option, an edit list / MKV codec delay so players start at `from`),
  audio trimmed to the range, subtitles in range, timestamps rebased to 0,
  chapters inside the range; then write MKV or MP4 from `(file, media,
  plan)`. Big outputs: write in pieces (`appendData`) to keep memory low.
- **GIF**: GIF89a encoder (LZW per the GIF89a spec), palette per frame or
  global by a median-cut or octree quantiser of your own, optional
  Floyd–Steinberg dithering, frame delays, looping, from RGBA pixel lists
  (the lead will feed rendered frames).
- Tests: write clips from the fixtures and check them with ffprobe
  (packets, timestamps, md5 of payloads equal to the source's), re-open
  them with `demux.open`, decode a written H.264/AAC clip with ffmpeg; GIF
  decoded by python (stdlib only) or ffmpeg back to the same frames
  (without dithering).

## disc: module `disc/` — test `tests/disc`

Only touch `disc/`, `tests/disc/`, `build/scratch/disc/`.

- **DVD-Video folders** (`VIDEO_TS`): VMG and VTS IFO parsing (from the
  public DVD-Video format descriptions — e.g. the "DVD-Video Information"
  pages at dvd.sourceforge.net / mpucoder; write your own code): title
  table, program chains, programs → chapters, cell playback (angles: first
  angle), audio streams (codec, language, channels) and subpicture
  streams (language, palette as YCbCr → used by dvdsub), VOBU/cell sector
  addresses → `disc.Title` with `segments: [(path, fromByte, toByte)]`
  over the VTS_xx_1…9.VOB files, chapter times, duration.
- **Blu-ray folders** (`BDMV`): index.bdmv (titles), `PLAYLIST/*.mpls`
  (play items → clip names with in/out times, chapter marks, STN table:
  streams with PIDs, codecs, languages), `CLIPINF/*.clpi` (stream info and
  the EP map: PTS → source packet number, for seeking), main feature
  detection (longest playlist, skip duplicates/obfuscation playlists) →
  `disc.Title` with m2ts segments and times. (Reading 20–60 GB m2ts needs
  ranged reads that Tessel lacks; the parsing and the title model are the
  job; note what playback will need.)
- **ISO images**: reading the ISO 9660 / UDF file listing of a `.iso` to
  find VIDEO_TS/BDMV inside (UDF 2.50 for Blu-ray is a stretch goal).
- Tests: there are no commercial discs to use: build small DVD folders
  with python from your own understanding of the IFO format and check the
  structure round-trips, and parse any public sample IFO/MPLS files you
  can find with permissive licences; make sure malformed files never stop
  the program.

## Report

When done, reply with: public API, features, tests and what they check,
timings, known gaps, anything added to NEEDED.md / TESSEL_ISSUES.md, and
what the lead needs to do to wire it into the player.
