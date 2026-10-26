# Reel — round 4 builders: the remaining codecs

Read `build/BRIEF.md` first: every rule there applies (Tessel docs only from
`build/tessel-docs/`, own files only, author/date headers, tests ending
`<name>: N of M passed`, Tessel problems to `build/TESSEL_ISSUES.md`, no git,
no loose pkill, ffmpeg only from scripts/shell as a reference, never open
GUI windows, never run bare `tessel`). Its "Common API shapes" are the API
every decoder keeps. `build/TESSEL_ISSUES.md` lists speed traps found since
round 1: module-level `let` lists are slow to read (copy to a local),
re-passing `bind` parameters is slow, building big lists is slow (reuse
buffers), `wrappingAdd` is ~3× slower than `+`, `[]` assigned to a list
field allocates. The finished decoders are good examples to read — `vp9/`
(newest, staged), `hevc/`, `h264/`, `mpeg4/`, `ac3/`, `dts/`, `aac/` —
but don't edit or import other builders' modules unless your section says
so.

Codec names, `Track.extra` forms and the demuxers are already set up for
you (`core/media.tsl` lists every name). `demux/ivf.tsl` opens IVF files
(the AV1/VP8/VP9 conformance vectors). This Mac has 15 cores and other
builders run at the same time: keep test runs to a few minutes.

**Speed matters.** The player decodes in Tessel `background` jobs (no
shared memory). Video decoders that are heavy at 1080p are built, like
`vp9/`, as a **Parser** (entropy decoding into plain per-block arrays) and
a **Reconstructor** (prediction, transforms, filters, output) plus the
ordinary Decoder that chains them, so the player runs the two on two cores:
`newPipeline(track) -> Result<Pipeline>` with `parser`/`reconstructor`,
`Parser.parse(packet, pts:, dts:, key:) -> [ParsedFrame]`, `flush()`,
`reset()`, `skipNonReference`, `Reconstructor.reconstruct(ParsedFrame) ->
[core.Picture]`, `reset()` (read `vp9/api.tsl`). Goal for staged decoders:
max(parse, reconstruct) ≤ 30 ms per picture at 1080p 8-bit on movie-like
clips; print `time` lines for 720p and 1080p. Every decoder also gets
`public fn streamInfo(_ track: core.Track) -> String` (e.g. "AV1 Main,
1920×1080, 10-bit", "TrueHD 7.1 (Atmos), 48 kHz, 24-bit").

Damage never stops the program: conceal, add a warning, go on.

---

## av1: module `av1/` — test `tests/av1`

Only touch `av1/`, `tests/av1/`, `build/scratch/av1/`, `build/conformance/av1/`.

A bit-exact AV1 decoder (AV1 Bitstream & Decoding Process Specification,
with errata), **Main profile** (8 and 10-bit 4:2:0 and monochrome) first;
High (4:4:4) and Professional (4:2:2, 12-bit) if cheap after that.
Staged (Parser + Reconstructor) as described above.

- Packets: MP4/MKV/WebM samples and IVF frames are temporal units of
  low-overhead OBUs (`obu_has_size_field`); `Track.extra` is the `av1C`
  box body (its configOBUs hold the sequence header) or empty. Also accept
  Annex B length-delimited units when the track's tag says so (optional).
- Everything a real stream uses: sequence/frame/tile-group OBUs, frame
  header (all fields, reference frame update, `show_existing_frame`,
  `frame_refs_short_signaling`, `disable_cdf_update`, error-resilient
  mode, intra-only frames, superres, frame size with refs, render size),
  the symbol (range) decoder and CDF adaptation with saved/loaded contexts,
  tiles (uniform and explicit; decode them in order), partition, all intra
  modes incl. CFL, palette, intra block copy, filter intra, directional
  edge filtering/upsampling; inter: single and compound (average,
  distance, wedge, diff-weighted), OBMC, warped motion (local and global),
  inter-intra, the 8-tap filters with dual filter, scaled references,
  MV prediction (ref MV stack), motion field projection (`use_ref_frame_mvs`);
  segmentation, delta q / delta lf, quantizer matrices, all transforms
  (DCT/ADST/flipADST/identity 4–64, WHT lossless), loop filter, CDEF, loop
  restoration (Wiener, self-guided), superres upscaling, **film grain
  synthesis** (applied to the output picture, as dav1d and libaom do — the
  conformance MD5s include it).
- Output `core.Picture` 8 or 10-bit with pts of the temporal unit that
  showed it, `key`, `matrix` and `fullRange` from the colour config.
- Fixtures: `tests/fixtures/t.av1.ivf` (+ make your own with ffmpeg's
  `libsvtav1`: 8-bit, `-pix_fmt yuv420p10le`, `-svtav1-params
  film-grain=8`, tiles, odd sizes; references from ffmpeg's `libdav1d`
  decoder as framemd5). Conformance: the libaom test vectors
  (`av1-1-b8-*` and `av1-1-b10-*` .ivf/.mkv with their .md5, at
  https://storage.googleapis.com/aom-test-data/ — e.g.
  av1-1-b8-01-size-16x16.ivf … , -02-allintra, -03-sizeup/-sizedown,
  -04-cdfupdate, -05-mv, -06-mfmv, -22-svc-L1T2/L2T1/L2T2, -23-film_grain-50,
  av1-1-b10-00-quantizer-*, -23-film_grain-50, -24-*) into
  `build/conformance/av1/`; list which pass. Bit-exact everywhere.

## dolby: module `truehd/`, `demux/thd.tsl`, E-AC-3 7.1 in `ac3/` — tests `tests/truehd`, `tests/ac3`

Only touch `truehd/`, `demux/thd.tsl` (replace the stub; prefix private
names `thd`), `ac3/`, `tests/truehd/`, `tests/ac3/` (keep its existing
checks passing), `build/scratch/dolby/`, `build/conformance/dolby/`.

1. **TrueHD and MLP** (codecs "truehd" and "mlp"), the audio decoder API:
   major sync and restart headers, substreams (decode the one with the most
   channels up to 7.1, as ffmpeg's default; Atmos streams: their 7.1 bed,
   ignore the object extension substream), matrixing, filters (FIR/IIR),
   Huffman and LSB bypass, noise shaping/dither, channel assignment →
   WAV-order layout, 16/24-bit output, the check bytes / CRCs (warn on
   mismatch). **Bit-exact** with ffmpeg. Track rate/channels from the first
   major sync when the container doesn't say.
2. **`demux/thd.tsl` `thdOpen`**: raw .thd/.mlp files (access units found
   by their length field, major sync for rate/channels/keyframes, pts in
   samples); TrueHD inside MKV, M2TS (stream type 0x83, which may carry an
   AC-3 core interleaved — split it off as its own "ac3" track when present
   is a bonus) and MP4 (`mlpa`) already arrive as "truehd" tracks: check
   them through `demux.open`.
3. **E-AC-3 7.1**: dependent substreams (`strmtyp` 1) after the
   independent one, channel map (`chanmap`) → the extra channels (Lrs/Rrs,
   Lw/Rw, Cvh …) in WAV order, as ffmpeg outputs 7.1; also check E-AC-3
   with several independent programs (decode program 0). Keep all existing
   ac3 tests passing.
- Fixtures: ffmpeg encodes TrueHD and MLP (`-c:a truehd -strict -2`,
  `-c:a mlp -strict -2`; stereo, 5.1, 7.1 if allowed, 16/24-bit, 48/96 kHz)
  into .thd/.mkv/.mp4/.m2ts; E-AC-3 7.1 and Atmos TrueHD can't be made by
  ffmpeg — download FATE samples (https://fate-suite.ffmpeg.org/truehd/,
  /eac3/, /lossless-audio/) into `build/conformance/dolby/`, references
  with ffmpeg as f32 (and s32 for lossless bit-exactness); keep small cuts
  as committed fixtures under `tests/truehd/fixtures/`.
- Speed: print × real time for TrueHD 7.1 and E-AC-3 7.1.

## vp8theora: modules `vp8/` and `theora/` — tests `tests/vp8`, `tests/theora`

Only touch `vp8/`, `theora/`, their tests, `build/scratch/vp8theora/`,
`build/conformance/vp8theora/`.

1. **VP8** (RFC 6386), bit-exact: key and inter frames, bool decoder,
   probability updates, segmentation, loop filter (normal and simple,
   deltas), partitions, intra/inter prediction (6-tap and bilinear, the
   "full pixel" variant), MV decoding, golden/altref with sign bias,
   horizontal/vertical scaling bits (ignored for output, as ffmpeg), odd
   sizes, alpha-less. Output 8-bit 4:2:0 with pts. Staged
   (Parser/Reconstructor) if 1080p doesn't reach the goal single-threaded.
   Fixtures: `tests/fixtures/vp8.webm`, `t.vp8.ivf`, more with ffmpeg's
   `libvpx` (`-auto-alt-ref 1`, tokens partitions `-token-parts 3`, error
   resilient, odd sizes); conformance: the libvpx test vectors
   `vp80-00-comprehensive-001.ivf` … `-018` (+ .md5), and
   `vp80-01-intra-*`, `-02-inter-*`, `-03-segmentation-*`, `-05-sharpness-*`
   at https://storage.googleapis.com/downloads.webmproject.org/test_data/libvpx/
   into `build/conformance/vp8theora/`.
2. **Theora** (Theora I specification), bit-exact with ffmpeg: the three
   headers from `Track.extra` (Xiph form as for Vorbis), all frame types,
   DCT token decoding, Huffman tables from the setup header, quantizer
   matrices, DC prediction, motion vectors (incl. 4MV), loop filter,
   4:2:0/4:2:2/4:4:4 pixel formats, picture offsets (crop to the picture
   region). Fixtures: ffmpeg here has no Theora encoder — download FATE
   samples (https://fate-suite.ffmpeg.org/theora/) and Xiph test files;
   references with ffmpeg framemd5. Check Ogg Theora through `demux.open`.

## wmv: module `wmv/` — test `tests/wmv`

Only touch `wmv/`, `tests/wmv/`, `build/scratch/wmv/`, `build/conformance/wmv/`.

Microsoft's video codecs, one module (they share a lot): **msmpeg4v1,
msmpeg4v2, msmpeg4v3** (DivX ;-) 3, common in old AVIs), **wmv1**
(WMV7), **wmv2** (WMV8), **wmv3** (WMV9 = VC-1 Simple/Main, incl.
range reduction, multires, beta-features ffmpeg supports), and **vc1**
(VC-1 Advanced: sequence/entry-point headers, progressive, interlaced
frame and field pictures, B/BI pictures, overlap smoothing, in-loop
deblocking, intensity compensation, pan-scan ignored). Bit-exact with
ffmpeg. `Track.extra`: for wmv3 the 4+ bytes of the sequence header
(STRUCT_C from the BITMAPINFOHEADER tail / ASF); for vc1 the sequence and
entry-point headers (with start codes, from the WVC1 extra / ASF / MKV
CodecPrivate after its BITMAPINFOHEADER), or empty when they're in the
stream (TS stream type 0xEA, raw .vc1 Annex E). Staged
(Parser/Reconstructor) for vc1/wmv3 if 1080p needs it.
- Fixtures: ffmpeg encodes msmpeg4v2, msmpeg4 (v3), wmv1, wmv2 into AVI
  and MKV (`-c:v msmpeg4 …`); VC-1 and WMV9 can't be encoded — download
  FATE samples (https://fate-suite.ffmpeg.org/vc1/, /wmv8/, /msmpeg4/ and
  whatever else has WMV3/VC-1/DIV3 streams) into `build/conformance/wmv/`; ASF
  files are opened by the wma builder's demuxer, which may not be ready:
  remux them with `ffmpeg -c copy` into MKV/AVI for your tests, and once
  `demux.open` handles .wmv (check `demux/asf.tsl`), test a few through it.

## wma: module `wma/` and `demux/asf.tsl` — tests `tests/wma`, `tests/asf`

Only touch `wma/`, `demux/asf.tsl` (replace the stub; prefix private
names `asf`), `tests/wma/`, `tests/asf/`, `build/scratch/wma/`,
`build/conformance/wma/`.

1. **`demux/asf.tsl` `asfOpen`** (ASF specification 1.20): header object
   (file properties, stream properties for audio (WAVEFORMATEX → codec as
   in `demux/mkv.tsl`'s `mkvWaveFormat`: 0x160 "wmav1", 0x161 "wmav2",
   0x162 "wmapro", 0x163 "wmalossless", plus mp3/pcm/ac3…) and video
   (BITMAPINFOHEADER fourcc: WMV1/WMV2/WMV3/WVC1/WMVA/MP43/MP42/MPG4 →
   names in core/media.tsl; `extra` = the bytes after the 40-byte header),
   extended stream properties, header extension, content description and
   extended content description → tags (title, artist (Author), album
   (WM/AlbumTitle), date (WM/Year), genre, track (WM/TrackNumber)), cover
   art (WM/Picture), stream bitrate, language list, codec list), data
   object packets (error correction data, payload parsing information,
   single and multiple payloads, replicated data with media object size
   and presentation time, compressed payloads (sub-payloads), padding);
   media objects fragmented across payloads become one packet with
   `parts`; keyframe flag; pts from presentation time (ms) minus preroll;
   duration; seeking: keyframes from the simple index object when there.
   Refuse DRM-protected files with a clear error. Video and audio both.
2. **WMA** (the audio decoder API): **wmav1/wmav2** (MDCT, exponents
   (LSP and Huffman), run-level coefficients, noise coding, block
   switching, M/S stereo) — float decoders, aim ≥ 90 dB vs ffmpeg;
   **wmapro** (WMA 9 Professional: tiles, channel transforms, subframes,
   up to 7.1, 24-bit) ≥ 90 dB; **wmalossless** bit-exact. `wmavoice` not
   needed.
- Fixtures: ffmpeg encodes wmav1/wmav2 audio and wmv1/wmv2 video into ASF
  (`-f asf`, .wma/.wmv); WMA Pro and Lossless can't be encoded — download
  FATE samples (https://fate-suite.ffmpeg.org/wmapro/, /lossless-audio/,
  /wmv8/, /vc1/ for ASF with VC-1) into `build/conformance/wma/`;
  references with ffmpeg (f32, s32 for lossless) and ffprobe packets.
- Speed: print × real time for wmav2 stereo and wmapro 5.1.

## pro: modules `prores/` and `dnxhd/` — tests `tests/prores`, `tests/dnxhd`

Only touch `prores/`, `dnxhd/`, their tests, `build/scratch/pro/`,
`build/conformance/pro/`.

Intra-only editing codecs, the video decoder API (each picture is a
keyframe; no reordering). Bit-exact with ffmpeg.
1. **ProRes** (SMPTE RDD 36): 422 Proxy/LT/Standard/HQ and 4444/4444 XQ
   (alpha decoded and dropped is fine — `core.Picture` has no alpha),
   progressive and interlaced (two fields per frame, top or bottom first),
   slices, quantization matrices, the entropy coding (Rice/exp-Golomb
   hybrid), 10-bit output (`depth` 10, `.yuv422` / `.yuv444`), colour
   from the frame header.
2. **DNxHD / DNxHR** (SMPTE VC-3 / ST 2019-1): all compression IDs
   ffmpeg knows (DNxHD 1080/720 profiles, DNxHR LB/SQ/HQ/HQX/444), 8/10/12
   bit, 4:2:2 and 4:4:4, interlaced, ACT (adaptive colour transform) and
   mixed-bit-depth macroblocks as ffmpeg supports them. Track codec
   "dnxhd" (MOV `AVdn`/`AVdh`, MXF not needed).
- Both are slice-parallel by nature: make them fast (1080p ≤ 30 ms per
  frame single-threaded if you can; staged not needed — say if a split
  would help).
- Fixtures: ffmpeg encodes them (`-c:v prores_ks -profile:v 0..5`,
  `-c:v prores_aw`, interlaced `-flags +ildct`, `-c:v dnxhd -profile:v
  dnxhr_lb/sq/hq/hqx/444` and DNxHD bitrates `-b:v 36M` at 1080p) into MOV;
  FATE samples (https://fate-suite.ffmpeg.org/prores/, /dnxhd/) into
  `build/conformance/pro/`. Check them through `demux.open` (MOV).

---

## Report

When done, reply with: API, features, which fixtures/conformance streams
pass (bit-exact or SNR), timings, known gaps, anything added to NEEDED.md /
TESSEL_ISSUES.md. The lead wires every codec into the player afterwards.
