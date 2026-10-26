# Reel — engine builders' brief (round 1)

Reel is a VLC-like media player written **entirely in Tessel 0.15.0** (the
project at `~/Dev/reel`, pinned in `tessel.toml`). No FFmpeg, no native
helpers, no changes to Tessel: every container, codec, subtitle format and
the renderer are written in Tessel. This round builds the UI-free engine,
one module per builder, in parallel. The player and the app come next round
and will call your public API exactly as given here.

## Rules (all builders)

1. **Tessel knowledge comes only from the published docs**, saved in
   `~/Dev/reel/build/tessel-docs/` (start with `reference_grammar.md`,
   `language_*.md`, `reference_stdlib.md`). **Never read or touch
   `~/Dev/tessel` or `~/.tessel`.** Never run `tessel` with no arguments (it
   opens the IDE window). Never open GUI windows.
2. **Only edit your own files**: your module folder(s), `tests/<your
   test>/`, and scratch under `build/scratch/<you>/`. `core/`, `testkit/`,
   `demux/api.tsl` and `tools/` are the shared contract: read them closely,
   don't change them. If you need a change there, append the request to
   `build/NEEDED.md` (with your name) and work around it meanwhile.
3. Keep the public API in this brief exactly (you may add more public
   functions/fields, split into more files, add private helpers). Within a
   module all files share one namespace, so prefix private helpers (e.g.
   `mp4…`, `cabac…`) to avoid clashes — the demux module is shared by
   three builders.
4. Every source file starts with a comment block saying what the file is,
   then `// Author: Alexius Academia` and `// Date: 2026-10-25`. Write
   comments for a reader who knows programming but not the format: name
   the spec section a piece of code follows.
5. Modules import core with `import "../core"`; names are written
   `core.Track`, `core.bitReader(…)`.
6. **Tests**: `tests/<name>/main.tsl` is a `fn main()` program importing
   your module (`import "../../<module>"`, `"../../core"`,
   `"../../testkit"`), printing `FAIL: …` for each failed check and ending
   with exactly one line `<name>: N of M passed`. Print timings as
   `time <what>: N ms` (not checks). Run from `~/Dev/reel`:
   `tessel run tests/<name>`; `tessel check <module>` type-checks fast;
   `tests/run.sh <name>` runs it the way the lead will. Build heavy tests
   with `tessel build tests/<name> -o build/scratch/<you>/t && ./build/scratch/<you>/t`
   if `tessel run` is slow to compile.
7. **References**: `tests/fixtures/` holds clips made by
   `tools/make_fixtures.sh` with ffmpeg 8.1, and ffmpeg's answers for each
   (read `tools/make_fixtures.sh` and `testkit/testkit.tsl`):
   `F.ref.json` (tracks, packets with byte positions, tags, chapters, via
   `testkit.loadRef`), `F.v.framemd5` (each picture's md5,
   `testkit.frameMd5s`, compare with `testkit.pictureMd5`), `F.v.yuv` (first
   10 pictures raw, `testkit.referenceYuv`, compare with `testkit.psnr`),
   `F.a.f32` (decoded samples, `testkit.referenceSamples`, compare with
   `testkit.snr`). `testkit.mediaFromRef(file, ref)` gives decoder builders
   packets without waiting for the demuxers (packets stored in one piece:
   MP4, MKV, AVI, raw; not Ogg or TS). You may run `ffmpeg`/`ffprobe` and
   Python 3 (`python3 -I`) **from scripts and the shell** to make extra
   fixtures into `build/scratch/<you>/` or `tests/<name>/fixtures/` (keep
   committed fixtures small, a few hundred KB). Public conformance suites
   may be downloaded into `build/conformance/<you>/` (for example the JVT
   H.264 suite at https://www.itu.int/wftp3/av-arch/jvt-site/draft_conformance/).
   Reel's own code never calls ffmpeg.
8. **Tessel bugs**: if Tessel misbehaves (compiler crash, wrong result, a
   documented feature that doesn't work, something very slow), make a minimal
   repro under `build/scratch/<you>/`, work around it, and append it to
   `build/TESSEL_ISSUES.md` (what, repro path, workaround). Don't file
   issues yourself.
9. Don't touch git. Don't kill processes by loose patterns (no `pkill -f`,
   no `killall`); kill only PIDs you started.
10. When done, reply with: what you built (public API, formats/features
   supported), test count, timings, known gaps, and anything you put in
   NEEDED.md / TESSEL_ISSUES.md.

## Facts about this Tessel (measured on this Mac, M-series)

- Code compiles to native code through LLVM. Reading 8M bits with
  `core.BitReader` takes ~5 ms; writing a 1920×1080 plane of Ints through a
  struct method ~1.3 ms. **Allocating small lists inside hot loops is slow**
  (an IDCT that made a 16-item list per 4×4 block ran 10× slower than it
  should): keep scratch lists as fields of your decoder struct and reuse
  them; write `self.buf[i] = v` in place.
- Ints are 64-bit. `+ - *` **overflow stops the program** (keep math in
  range; `wrappingAdd`/`wrappingMultiply` exist). Shifts wrap like C;
  `>>` is arithmetic (`-7 >> 1 == -4`); `/` and `%` truncate toward zero
  like C (`-7 / 2 == -3`, `-7 % 2 == -1`). `~`, `&`, `|`, `^` as in C.
  There is no `?:` operator: use `if c { a } else { b }`, `min`, `max`.
- Floats are 64-bit. Math: `sqrt pow exp log log10 sin cos tan asin acos
  atan atan2 floor ceil round abs min max pi`.
- `Data` is immutable bytes with `data[i]`, `slice(from:to:)`,
  `uint16/uint32/int32/int64/float32/float64(at:bigEndian:)`, `latin1`,
  `text`, `+`, `append(byte:)`, `append(_:)`, `bytes` (→ `[Int]`),
  `compressed/decompressed("zlib"|"deflate"|"gzip")`, `hash("md5")`.
  Building a Data a byte at a time with `append(byte:)` is fine.
- Lists and Data are copy-on-write; writing through a `var`, a field of
  `self` in a method, or a `bind` parameter is in place. Methods that change
  `self` just assign to fields (no `mutating` keyword). There are no
  globals; module-level `let` constants (including lists) are allowed and
  cheap.
- Values in decoder structs must be plain data (no closures, no
  interfaces), so the player can hand a decoder to `background` work and
  get it back.
- `readData(path)` reads a whole file. There is no partial file read, so
  demuxers get the whole file as one `Data`.

## The contract (read it all)

- `core/media.tsl`: `Media`, `Track`, `PacketRef`, `Chapter`,
  `Attachment`, `PcmFormat`, `packetBytes`, `noTime`, `rescale`,
  `seconds`, `ticks`. **Codec names and the form of `Track.extra` per codec
  are defined there** — demuxers produce exactly that, decoders expect
  exactly that.
- `core/picture.tsl`: `Picture` (planes of Int samples with strides and
  offsets), `Chroma`, `ColorMatrix`, `pictureBytes`, `zeros`, `filled`.
- `core/samples.tsl`: `Samples` (interleaved Floats in −1…1, WAV channel
  order, `layout` names).
- `core/bits.tsl`: `BitReader` (MSB first, `bits peek flag signed long
  skip ue se alignToByte seek moreRbspData position left overrun`),
  `LsbReader`, `ByteReader`, `unescapeRbsp`.
- `demux/api.tsl`: `demux.open`, `demux.sniff`, `demux.keyBefore`; it calls
  each container's open function (stubs now in `demux/*.tsl`).

## Common API shapes

**Every video decoder module** (`h264`, `mpeg12`, `jpeg`, `mpeg4`):

```text
public struct Decoder { … plain data … }
public fn newDecoder(_ track: core.Track) -> Result<Decoder>
  fn decode(_ packet: Data, pts: Int, dts: Int, key: Bool) -> [core.Picture]
  fn flush() -> [core.Picture]     // end of stream: pictures still held
  fn reset()                       // after a seek: drop references and
                                   // held pictures, wait for a keyframe
  skipNonReference: Bool           // field: when true, don't decode
                                   // pictures nothing refers to (B-frames)
  warnings: [String]               // field: damaged data found (decoding
                                   // goes on: conceal and continue)
```

`decode` returns the pictures that are ready, **in display order**, each
with the `pts` of the packet it came from (reordered with it) and
`key`, `sarNum/sarDen`, `matrix`, `fullRange` set from the stream (use
`core.guessMatrix` when the stream doesn't say). A damaged packet never
stops the program: conceal (copy from the previous picture), add a
warning, go on.

**Every audio decoder module** (`mpa`, `lossless`, `aac`, `vorbis`, `opus`,
`ac3`):

```text
public struct Decoder { … plain data … }
public fn newDecoder(_ track: core.Track) -> Result<Decoder>
  fn decode(_ packet: Data, pts: Int) -> core.Samples   // may be empty
  fn flush() -> core.Samples
  fn reset()
  rate: Int, channels: Int, layout: [String]   // fields, right after
                                   // newDecoder when the setup says, else
                                   // after the first decode
  delay: Int                       // field: priming frames at the start
                                   // the player should drop (encoder
                                   // delay / Opus pre-skip), when known
  warnings: [String]
```

Output samples in WAV order with `layout` names (core/samples.tsl).
Lossless codecs must be bit-exact (`snr` 150). Lossy ones: compare with
ffmpeg's output; containers trim priming differently, so find the best
alignment within ±4096 frames and report it; aim for SNR ≥ 90 dB (float
decoders should agree to rounding), at least 60 dB.

## Module assignments

### demux-a: `demux/mp4.tsl`, `demux/wav.tsl`, `demux/raw.tsl` — test `tests/demux_a`
- **MP4/MOV/M4A/3GP** (`mp4Open`): box tree; `moov/trak/mdia/minf/stbl`
  sample tables (stsz/stz2, stco/co64, stsc, stts, ctts, stss; no stss =
  all key), edit lists (`elst`: shift pts so the first shown sample is at 0;
  keep the media time offset for audio priming), fragmented MP4 (`moof/
  traf/tfhd/tfdt/trun`, `mvex/trex` defaults, `sidx` ignored), codecs
  avc1/avc3 (avcC), hvc1/hev1 (hvcC), mp4a (esds → AudioSpecificConfig;
  object types 0x40 aac, 0x69/0x6B mp3), alac, fLaC (dfLa), Opus (dOps →
  OpusHead), ac-3/ec-3, mp4v (esds → mpeg4 extra), jpeg/mjpa/mjpb, lpcm
  and twos/sowt/in24/fl32 (pcm), ulaw/alaw, tx3g/text (subtitle), `wvtt`.
  Track language (mdhd, also `elng`), title (udta name), handler, rotation
  from `tkhd` matrix, `pasp`, `colr`. iTunes tags (`moov/udta/meta/ilst`:
  ©nam ©ART aART ©alb ©day ©gen trkn disk ©cmt ©wrt ©too cprt, covr →
  `Media.cover`), QuickTime `udta` ©xxx strings. Chapters: Nero `chpl` and
  QuickTime chapter tracks (`tref/chap` → a text track; don't list it as a
  subtitle). Packets in file order (by offset), interleaved across tracks.
  **Speed**: a 2-hour movie has ~500k samples; aim for under 0.5 s.
  Measure on a synthetic big moov (make one with ffmpeg: 1 h of 2 fps tiny
  video and audio is fine).
- **WAV/AIFF** (`wavOpen`): RIFF/RF64 WAVE (fmt PCM 1, float 3, alaw 6,
  ulaw 7, EXTENSIBLE 0xFFFE with channel mask → layout), `LIST/INFO` and
  `id3 ` tags, AIFF/AIFC (COMM with 80-bit float rate, SSND, `sowt`/`fl32`/
  `NONE`, NAME/AUTH chunks). Packets: blocks of ~4096 frames.
- **Raw elementary streams** (`rawOpen(file, format:)`): mp3/mp2/mp1
  (frame sync with validation of the next header; ID3v2.2/2.3/2.4 incl.
  unsynchronisation, APIC → cover, TXXX, COMM; ID3v1; APEv2 skip; Xing/Info
  and VBRI → duration and seek; LAME tag → `delay` hint in Track? put
  encoder delay/padding into `Media.tags["delay"]`/`["padding"]` as
  numbers), AAC ADTS (`adts = true`, extra empty), FLAC native (STREAMINFO,
  VORBIS_COMMENT tags, PICTURE → cover, SEEKTABLE; frames found by sync +
  CRC-8 header check; `extra` = "fLaC"+metadata blocks), AC-3/E-AC-3
  (syncframes), H.264/HEVC Annex B (access units split at AUD or first
  slice of a new picture; pts from frame rate 25 when unknown).
- Test against every fixture's `.ref.json`: same tracks, codecs, sizes,
  rates, languages, tags, cover, chapters, and packet count/sizes/offsets/
  pts/dts/key flags (ffmpeg's pts may be shifted by edit lists — explain
  any systematic difference in comments, match it where it's sensible).

### demux-b: `demux/mkv.tsl`, `demux/ogg.tsl` — test `tests/demux_b`
- **Matroska/WebM** (`mkvOpen`): EBML with unknown-size elements (live
  WebM), SeekHead, Info (TimestampScale, Duration, Title, MuxingApp),
  Tracks (CodecID → codec names: V_MPEG4/ISO/AVC, V_MPEGH/ISO/HEVC, V_VP8,
  V_VP9, V_AV1, V_MPEG1/2, V_MS/VFW/FOURCC (BITMAPINFOHEADER), V_THEORA,
  V_MJPEG, A_AAC (+ legacy A_AAC/MPEG4/LC… with no CodecPrivate: build the
  AudioSpecificConfig), A_MPEG/L3, A_MPEG/L2, A_FLAC, A_VORBIS (Xiph lacing
  in CodecPrivate → core's 3-header form), A_OPUS, A_AC3, A_EAC3, A_DTS,
  A_PCM/INT/LIT|BIG, A_PCM/FLOAT/IEEE, A_ALAC, A_MS/ACM, S_TEXT/UTF8 (srt),
  S_TEXT/ASS|SSA (ass, extra = header), S_TEXT/WEBVTT, S_HDMV/PGS (pgs),
  S_VOBSUB (dvdsub; extra = the idx text)), Video (PixelWidth/Height,
  Display size → SAR, Colour), Audio (SamplingFrequency,
  OutputSamplingFrequency for SBR, Channels, BitDepth), Language (and
  LanguageBCP47), Name, FlagDefault/FlagForced, ContentEncodings (header
  stripping → `Track.prefix`; zlib compression → decompress into...
  packets can't hold changed bytes: put such tracks' packets' bytes into
  `Media.attachments`? No — mark the track codec "unknown:zlib" and warn;
  it's rare), Clusters with SimpleBlock and BlockGroup (Block,
  BlockDuration, ReferenceBlock → key flag), all lacings (Xiph, EBML,
  fixed; each laced frame is one PacketRef with its own byte range and
  pts spread by DefaultDuration), Cues (use them for nothing but checks:
  packets come from scanning clusters), Chapters (EditionEntry/
  ChapterAtom, nested, ChapterDisplay strings), Tags (global → `tags`;
  per-track ones you may ignore), Attachments (fonts, cover art: an
  attachment named cover.* → `Media.cover` too). Timestamps: track
  timescale = 1e9 / TimestampScale (normally 1000); pts = cluster time +
  block offset. MKV has no dts: set dts = noTime. Scan big files quickly:
  skip element bodies by size; aim ≤ 1 s for a 4 GB file's ~100k clusters
  (measure on a synthetic long file).
- **Ogg** (`oggOpen`): pages (CRC check, warn on bad), packets across
  pages (`parts`), multiple logical streams (chained Ogg: new streams after
  the first ends — list them as more tracks with a warning), Vorbis (3
  headers → extra; comment header → tags; METADATA_BLOCK_PICTURE → cover;
  pts from granule positions: work back from each page's granule using
  each packet's block size — **this needs the Vorbis mode/blocksize info
  from the setup header**; parse just enough of it (mode blockflags), or
  approximate and document), Opus (OpusHead → extra, OpusTags → tags,
  granule − pre-skip, 48 kHz timescale; packet durations from the TOC
  byte), Ogg FLAC (0x7F "FLAC" mapping), Theora (3 headers, granule shift).
  Duration from the last page's granule.
- Test against `.ref.json` for every MKV/WebM/Ogg/Opus fixture.

### demux-c: `demux/avi.tsl`, `demux/ts.tsl`, `demux/ps.tsl` — test `tests/demux_c`
- **AVI** (`aviOpen`): RIFF AVI/AVIX, hdrl/avih/strl (strh, strf:
  BITMAPINFOHEADER → codec from fourcc: H264/avc1/X264 h264, XVID/DIVX/DX50/
  FMP4/MP4V mpeg4, MJPG mjpeg, mpg2; WAVEFORMATEX → 0x55 mp3, 0x50 mp2,
  0x2000 ac3, 0xFF/0x1610 aac, 1 pcm, 3 float, 0x2001 dts), strn names,
  movi chunks, idx1 (offsets relative to movi or the file — detect),
  OpenDML indx/ix## super/standard indexes for files over 1 GB, no index →
  scan movi. Key flags from the index (AVIIF_KEYFRAME). Video pts = frame
  number × (dwScale/dwRate); audio pts from bytes (CBR) or block count
  (VBR mp3: nBlockAlign = 1152/576). DivX "packed bitstream" B-frames:
  leave as is (the mpeg4 decoder handles it), mark in a warning. Skip
  zero-size "drop" frames but keep their timing. INFO tags (INAM IART
  ICMT ICRD).
- **MPEG-TS** (`tsOpen`): 188-byte (and 192-byte M2TS, 204-byte) packets,
  sync recovery, PAT/PMT (program 1 or the first; descriptors: ISO 639
  language 0x0A, AC-3 0x6A, E-AC-3 0x7A, registration 0x05, DVB subtitle
  0x59, teletext 0x56 → other), stream types (0x1B h264, 0x24 hevc, 0x02/
  0x01 mpeg2/mpeg1, 0x10 mpeg4, 0x0F aac ADTS, 0x11 aac LATM →
  "unknown:latm", 0x03/0x04 mp2/mp3, 0x81/0x87 ac3/eac3 (and 0x06 with
  descriptors), 0x06 dvbsub, 0x90 pgs in M2TS), PES assembly across TS
  packets (`parts` byte ranges of payload only, PES header excluded), PTS/
  DTS at 90 kHz with 33-bit wraparound unwrapped, key flags (random access
  indicator, or IDR/I-picture detection in the payload start: for h264 look
  for NAL type 5 or recovery point SEI; for mpeg2 picture_coding_type 1),
  duration from first/last PCR or PTS. **Speed**: a 4 GB TS is 21M
  packets; aim for ≤ 2 s per GB.
- **MPEG-PS** (`psOpen`): pack headers (MPEG-1 and MPEG-2), system header,
  PES streams 0xE0–0xEF video (mpeg1/mpeg2 by sequence extension; h264 if
  PSM says), 0xC0–0xDF mpeg audio, private stream 1 (0x80–0x87 ac3, 0xA0
  lpcm, 0x20–0x3F dvd subtitles), PSM, PTS/DTS, packets split across PES
  (`parts`).
- Test against `.ref.json` for every AVI/TS/MPG fixture.

### h264: module `h264/` — test `tests/h264`
The most important and largest piece. Full ITU-T H.264 decoding for
**Constrained Baseline, Main and High profiles, 8-bit 4:2:0 (and 4:0:0)**,
bit-exact:
- NAL parsing for both forms (length-prefixed with the avcC's
  lengthSizeMinusOne when `track.extra` is an avcC; Annex B start codes when
  empty — then SPS/PPS come in the stream), emulation prevention, SPS
  (all fields incl. VUI: SAR, colour description → matrix, full range,
  bitstream restriction num_reorder_frames), PPS (incl. transform 8×8,
  scaling matrices, second chroma qp offset), SEI (recovery point only),
  AUD, end of sequence.
- Slice header, ref pic list init and modification for P and B, prediction
  weight tables, dec_ref_pic_marking (sliding window and all MMCOs,
  long-term refs), POC types 0/1/2, frame_num gaps.
- CAVLC and CABAC (all contexts, initialisation per slice QP and
  cabac_init_idc) macroblock layer: I_NxN (4×4 and 8×8), I_16x16, I_PCM,
  P and B partitions and sub-partitions, direct spatial and temporal, skip,
  mvd and mv prediction, ref idx, cbp, qp delta, residual blocks.
- Reconstruction: intra 4×4/8×8 (with reference filtering)/16×16/chroma
  prediction, inverse transforms 4×4/8×8/DC Hadamard, dequantisation with
  scaling lists, inter prediction (luma 6-tap quarter-sample, chroma
  eighth-sample bilinear, edge clamping), weighted prediction explicit and
  implicit, deblocking filter (bS derivation, alpha/beta/tc0 tables,
  slice-level disable and offsets, cross-slice disable).
- Multiple slices per picture; DPB with output order by POC
  (`max_num_reorder_frames` or the level's DPB size), bumping, flush; frame
  cropping → Picture width/height/offset.
- Interlaced (field pictures/PAFF, then MBAFF) **after** everything above
  passes: until then, detect field_pic_flag / mb_adaptive_frame_field and
  output something sensible (warn, skip or pair fields naively) without
  crashing. Do it in this round only if time allows.
- **Bit-exact**: every picture's md5 must equal the `.v.framemd5` of all
  progressive h264 fixtures (h264_baseline, main_bframes, high (mkv: use
  `testkit.mediaFromRef`), cavlc_slices, crop, weighted, intra, 720p,
  1080p, fragmented, multi, subs_*). Add JVT conformance bitstreams (in
  `build/conformance/h264/`, decode the progressive 8-bit 4:2:0 ones and
  compare with their reference YUV md5s) — list which pass.
- **Speed is a goal from the first line**: the player needs 720p30 in real
  time on one core (≤ 33 ms a picture, including everything) and the
  faster the better for 1080p. Print `time h264 720p: N ms per picture`
  and the same for 1080p. Design for it: plane buffers with padding so
  motion compensation doesn't clamp per sample in the common case,
  per-macroblock state in flat Int lists, no per-block allocation, CABAC
  decoding in a tight method on the decoder struct, tables as module
  `let` lists.
- Also expose `public fn parseAvcC(_ extra: Data) -> …` and
  `public fn spsInfo(_ track: core.Track) -> String` (profile, level, size,
  e.g. "High 4.0, 1920×1080, 4:2:0 8-bit") for the media info window.

### mpeg12 + jpeg: modules `mpeg12/` and `jpeg/` — tests `tests/mpeg12`, `tests/jpeg`
- **mpeg12**: MPEG-1 and MPEG-2 video (Main profile: I/P/B, frame and
  field pictures, frame/field DCT, all motion types incl. dual prime,
  4:2:0 (4:2:2 if easy), concealment motion vectors, alternate scan, q
  scale type, intra VLC format, sequence/GOP/picture headers + extensions,
  sequence display extension → matrix), interlaced output as frames
  (field pictures combined), display order reordering, pts per picture.
  IDCT: the IEEE-1180-conforming one; ffmpeg's may differ by a few least
  significant bits, so compare with `.v.yuv` by PSNR (≥ 45 dB expected,
  report it) and with framemd5 where they happen to match.
- **jpeg**: JPEG decoding for MJPEG video and cover art: baseline and
  progressive Huffman, 8-bit, any sampling (4:2:0, 4:2:2, 4:4:4, 4:1:1,
  gray), restart markers, DRI, Adobe/JFIF markers, EXIF orientation (report
  it), MJPEG AVI1 frames without DHT (use the default tables), CMYK may be
  skipped. Also `public fn decodeImage(_ data: Data) -> Result<core.Picture>`
  and `public fn toRgbaPixels(_ p: core.Picture) -> [Int]` (simple, for
  cover art; the render module does the fast path for video). Compare
  with `.v.yuv` (mjpeg.avi, mjpeg422.avi) by PSNR and with cover.jpg.

### mpeg4: module `mpeg4/` — test `tests/mpeg4`
- MPEG-4 Part 2 Visual, Simple and Advanced Simple profiles (Xvid/DivX):
  VOS/VO/VOL/VOP headers (from `track.extra` or the stream), I/P/B-VOPs,
  quarter-pel, interlaced, H.263 and MPEG quantisation with matrices, AC/DC
  prediction, 4MV, direct mode in B-VOPs, resync markers/data partitioning
  (decode or conceal), GMC (one warp point at least, or conceal), "not
  coded" VOPs, DivX packed bitstream (two VOPs in one AVI chunk → hold the
  second), user data (DivX/Xvid version for bug workarounds where cheap).
  Edge padding for unrestricted MVs. Compare with `.v.yuv` of mpeg4.avi by
  PSNR (≥ 45 dB) — ffmpeg's IDCT differs slightly. Speed: ≤ 10 ms per
  640×480 picture.

### audio-a: modules `mpa/` and `lossless/` — tests `tests/mpa`, `tests/lossless`
- **mpa**: MPEG-1/2/2.5 Layers I, II and III, all rates and modes (joint
  stereo MS/intensity), CRC skip, bit reservoir (main_data_begin across
  packets — keep the reservoir in the decoder), short/mixed blocks,
  hybrid synthesis (IMDCT + polyphase filterbank). Free format may be
  skipped. LAME/Xing tag frame: output nothing for it, read encoder
  delay/padding → `delay` (+529 decoder delay the way ffmpeg trims; match
  ffmpeg's alignment on mp3_cbr.mp3). Aim SNR ≥ 90 dB vs ffmpeg.
- **lossless**: FLAC (all subframe types, orders, Rice partitions, escape
  codes, wasted bits, stereo decorrelations, 8–32 bits, any block size,
  frame CRC-16 check → warn), ALAC (magic cookie, all channel elements, 16/
  20/24/32 bits), PCM from `Track.pcm` (8 unsigned, 16/24/32 signed, LE/BE,
  32/64 float), A-law and µ-law. Bit-exact.

### aac: module `aac/` — test `tests/aac`
- AAC-LC (AudioSpecificConfig or ADTS), mono/stereo/multichannel (channel
  configurations 1–7 and PCE; output WAV order: AAC's C L R Ls Rs LFE → FL
  FR FC LFE BL BR), SCE/CPE/LFE/CCE (CCE may be ignored)/DSE/FIL, ICS info,
  section data, scalefactors, spectral Huffman (all 11 codebooks + escape),
  M/S, intensity, PNS, TNS, IMDCT with sine and KBD windows, long/start/
  short/stop sequences, overlap-add. Then **HE-AAC v1 (SBR)** with implicit
  and explicit signalling (the output rate doubles; set `rate` once known —
  explicit from the ASC right away; implicit: assume SBR when the core rate
  is ≤ 24 kHz, as ffmpeg does) and **HE-AAC v2 (PS)**. Priming: 1024
  frames (2048 with SBR) — set `delay`; mp4 edit lists also trim it, the
  player will use the container's when there is one. Aim SNR ≥ 90 dB vs
  ffmpeg on aac_lc.m4a, aac_51.m4a, aac_mono.aac, he_aac.m4a, and the aac
  tracks inside mp4/mkv/ts fixtures.

### vorbis: module `vorbis/` — test `tests/vorbis`
- Vorbis I complete: identification/comment/setup headers from
  `track.extra` (core's 3-header form), codebooks (lookup types 1 and 2,
  sparse, ordered), floors 0 and 1, residues 0/1/2, mappings with channel
  coupling, modes, windowing and overlap-add, IMDCT. Also
  `public fn parseComments(_ packet: Data) -> [String: String]` (used by
  demuxers too — demux-b may write its own copy; that's fine). SNR ≥ 90 dB
  vs ffmpeg on vorbis.ogg (you need Ogg page reading in your test to get
  packets — write a small one in the test, or use `testkit` positions where
  they exist).

### opus: module `opus/` — test `tests/opus`
- RFC 6716 complete: range decoder, TOC and frame packing (codes 0–3,
  padding), SILK (NB/MB/WB, LPC, LTP, stereo prediction), CELT (all band
  allocation, PVQ, energy, transients, anti-collapse, postfilter), hybrid
  mode, redundancy frames, decoding at 48 kHz output, multichannel via
  channel mapping families 0, 1 (Vorbis order → WAV order) and 255
  (OpusHead in `track.extra`), pre-skip → `delay`, output gain. Packet loss
  concealment can be simple (repeat/fade). Aim SNR ≥ 60 dB vs ffmpeg (Opus
  decoders are allowed small differences; the RFC's conformance compares
  quality, not bits) on opus.opus, opus_mono.ogg, vp9.webm's audio, and
  multi.mkv's second audio track. You need Ogg page reading in your test.

### ac3: module `ac3/` — test `tests/ac3`
- AC-3 (A/52 all modes, coupling, rematrixing, exponent strategies, bit
  allocation, mantissa grouping, dither, dynamic range off by default,
  IMDCT 512/256 block switching, downmix not needed: output all channels in
  WAV order with LFE) and E-AC-3 (independent substream 0 at least,
  AHT, SPX, enhanced coupling, frame types; dependent substreams may be
  ignored with a warning). SNR ≥ 90 dB vs ffmpeg on ac3.ac3, eac3.eac3 and
  mpeg2.ts's ac3 track.

### subs: module `subs/` — test `tests/subs`
Everything Reel needs to show subtitles:
```text
public struct Span { text: String, bold, italic, underline, strike: Bool,
                     color: Int (rgba packed r<<24|g<<16|b<<8|a), outline:
                     Int, shadow: Int, font: String (""=default), size: Float
                     (1.0 = the style's size) }
public struct Cue { start: Float, end: Float (seconds), spans: [Span] (a
                    span with text "\n" breaks the line), align: Int (1–9,
                    numpad layout, 2 = bottom centre), marginL/R/V: Float
                    (fraction of the video's size), x/y: Float (−1 = not
                    positioned; else 0…1 of the video), style: String,
                    layer: Int, fadeIn/fadeOut: Float, bitmap: SubBitmap
                    (for PGS/DVD: x, y, w, h in video pixels and rgba
                    pixels; empty when it's text) }
public struct SubTrack { cues: [Cue], format: String, playResX/Y: Int }
public fn parseText(_ text: String, format: String) -> Result<SubTrack>
                    // "srt" "webvtt" "ass" files and MKV/MP4 text tracks
public fn decodeText(_ bytes: Data) -> String   // UTF-8, UTF-16 (BOM),
                    // else Windows-1252: subtitle files are often not UTF-8
public struct Decoder (for subtitle tracks in containers: "srt" "ass"
                    "webvtt" "tx3g" "text" "pgs" "dvdsub")
public fn newDecoder(_ track: core.Track) -> Result<Decoder>
  fn decode(_ packet: Data, start: Float, duration: Float) -> [Cue]
public fn activeCues(_ track: SubTrack, at: Float) -> [Cue]
public fn draw(_ g: Graphics, _ cues: [Cue], at: Float, x: Float, y: Float,
               width: Float, height: Float, scale: Float = 1.0)
                    // draws the cues over a video shown in that rectangle:
                    // white text with a dark outline by default, ASS styles
                    // when given, line wrapping, positioning, fades, bitmaps
public fn shifted(_ track: SubTrack, by: Float) -> SubTrack  // delay
```
Formats: SRT (with `<b><i><u><s><font color/face/size>`, `{\an8}`), WebVTT
(cue settings line/position/align, `<b><i><u><c.class><v>`, ignore
regions/styles blocks gracefully), ASS/SSA (Script Info PlayResX/Y, V4+/V4
Styles, Events, override tags `\b \i \u \s \c \1c \3c \4c \alpha \1a \fn
\fs \fscx \fscy \bord \shad \pos \an \a \move (as pos) \fad \fade(simple)
\k* (ignore) \N \n \h \r`; drawing commands `\p` may be skipped), MKV
ASS packets (ReadOrder,Layer,Style,Name,MarginL,MarginR,MarginV,Effect,
Text with the header from `track.extra`), tx3g (MP4: 2-byte length + text
+ style boxes), PGS (segments PCS/WDS/PDS/ODS, RLE, palette YCbCr → rgba,
composition timing: a cue ends when the next empty composition comes) and
DVD subtitles (SPU RLE, palette from the idx `extra`, control sequences).
Test with the fixtures (subs.srt, subs.ass, subs.vtt, subs_*.mkv,
subs_tx3g.mp4 via `testkit.mediaFromRef`), extra ones you write, and
drawing through `renderImage(path:…) { g in subs.draw(g, …) }` into PNGs
under `build/scratch/subs/` (check pixels: text drawn where expected).
Make your own small PGS sample if you can (ffmpeg can't encode PGS; you
may skip PGS tests with a note and test the parser on a hand-made segment
list).

### render: module `render/` — test `tests/render`
Turns decoded output into what the app shows and plays:
```text
public fn toRgba(_ p: core.Picture, width: Int, height: Int,
                 smooth: Bool = true) -> [Int]
    // the visible picture scaled to width×height, colour converted with
    // its matrix and range (BT.601/709/2020, video or full range, depth 8
    // to 12, 4:2:0/4:2:2/4:4:4/gray), packed r<<24|g<<16|b<<8|255 for
    // g.image(pixels:…). Chroma upsampled properly (not nearest).
    // smooth: bilinear scaling (area-averaged when shrinking by 2× or more);
    // otherwise nearest. Speed goals: 1920×1080 → 1920×1080 ≤ 12 ms,
    // → 1280×720 ≤ 8 ms, 1280×720 → 1280×720 ≤ 6 ms.
public fn rotate(_ pixels: [Int], width: Int, height: Int, degrees: Int) -> [Int]
public fn deinterlace(_ p: core.Picture) -> core.Picture   // simple
    // edge-directed line doubling of each field is fine (bob of the top
    // field); optional "blend"
public struct Mixer   // streaming: keeps state between blocks
public fn newMixer(channels: Int, rate: Int) -> Mixer
  fn process(_ s: core.Samples) -> core.Samples
    // downmix (or upmix mono) to `channels` (2 normally) with the ITU
    // coefficients by `layout` (centre −3 dB, surround −3 dB, LFE dropped),
    // then resample to `rate` (windowed-sinc polyphase, good quality;
    // 44.1↔48 kHz must sound clean: test a sweep, report the SNR/alias
    // rejection), soft-clip guarded.
public struct Stretcher  // streaming tempo change with pitch kept (WSOLA
public fn newStretcher(channels: Int, rate: Int) -> Stretcher  // or similar)
  fn setSpeed(_ speed: Float)          // 0.25 to 4.0
  fn process(_ s: core.Samples) -> core.Samples
  fn flush() -> core.Samples
public fn wavHeader(rate: Int, channels: Int, frames: Int, bits: Int = 16) -> Data
public fn wavData(_ s: core.Samples, bits: Int = 16) -> Data  // the
    // samples as WAV sample bytes (TPDF-dithered to 16 bits)
public fn wavFile(_ s: core.Samples) -> Data   // header + data
public fn gain(_ s: core.Samples, _ g: Float) -> core.Samples
public fn peak(_ s: core.Samples) -> Float
public fn levels(_ s: core.Samples, bands: Int) -> [Float]  // a spectrum
    // for an audio visualiser (FFT, log-spaced bands, 0…1)
```
Test colour conversion against ffmpeg (`ffmpeg -i X -frames:v 1 -pix_fmt
rgba -f rawvideo` with `-vf scale=out_color_matrix…` / or compare with
your own exact reference formulas: max error ≤ 2 per channel), scaling
quality, mixer coefficients, resampler quality, stretcher (speed 2 halves
the length within 1 %, pitch kept: dominant frequency of a 440 Hz tone
stays 440 ± 2 Hz), WAV round trip (write with wavFile, read back with
Tessel's readData).

## After this round

The player engine (`play/`: file loading in the background, decoders in
background jobs, A/V clock, audio through WAV chunks and `playSound`, frame
queue for `g.image`) and the app shell (VLC-like window, playlist, media
library, track/subtitle/speed menus, media info, network streams with
HLS) come next, written by the lead. Write your API so it is easy to call
from there.
