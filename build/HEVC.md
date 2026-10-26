# Reel — HEVC (H.265) decoder brief

Read `build/BRIEF.md` first: every rule there applies (Tessel docs only from
`build/tessel-docs/`, own files only, author/date headers, tests ending
`<name>: N of M passed`, Tessel problems to `build/TESSEL_ISSUES.md`, no git,
no loose pkill). The "Facts about this Tessel" section matters a lot here.

## Why

The user plays movie rips; most are HEVC (x265), often **Main 10 at 1080p**
(their test file: `Doctor.Strange.2016.1080p.BluRay.DDP5.1.x265.10bit-…mkv`).
Reel shows the sound but no picture for these today.

## Assignment: module `hevc/` — test `tests/hevc`

Only touch `hevc/`, `tests/hevc/`, `build/scratch/hevc/`,
`build/conformance/hevc/`.

A bit-exact ITU-T H.265 decoder for **Main and Main 10 profiles (4:2:0,
8 and 10 bit; also 4:0:0)**, with the video decoder API of the brief:

```text
public struct Decoder { … plain data … }
public fn newDecoder(_ track: core.Track) -> Result<Decoder>
  fn decode(_ packet: Data, pts: Int, dts: Int, key: Bool) -> [core.Picture]
  fn flush() -> [core.Picture]
  fn reset()
  skipNonReference: Bool
  warnings: [String]
public fn spsInfo(_ track: core.Track) -> String   // "Main 10 @ L4.1, 1920×1080, 4:2:0 10-bit"
```

- Input: `track.extra` is the hvcC box body (MP4 `hvcC`, MKV CodecPrivate):
  parameter-set arrays + lengthSizeMinusOne → length-prefixed NAL units;
  empty extra → Annex B start codes with VPS/SPS/PPS in the stream (TS).
- Everything Main/Main 10 streams use: VPS/SPS/PPS (incl. VUI → SAR,
  colour description → `core.ColorMatrix` (BT.2020 for UHD), full range;
  conformance window cropping → Picture width/height/offsets), slice
  segment headers (dependent slice segments, entry points), short-term RPS
  (incl. inter-RPS prediction) and long-term refs, POC, DPB with bumping by
  sps_max_num_reorder_pics / latency, RASL skipping after CRA/BLA at
  start or after `reset()`, NoOutputOfPriorPics.
- CABAC: all syntax elements and context initialisation; coding quadtree,
  transform tree, PCM, transform skip, sign data hiding, cu_qp_delta,
  chroma qp offsets, merge and AMVP (spatial and temporal candidates,
  collocated MVs), TMVP, weighted prediction.
- Reconstruction: intra (35 modes, reference substitution and filtering,
  strong intra smoothing, DST 4×4), transforms 4×4–32×32 with scaling lists,
  inter prediction (8-tap luma / 4-tap chroma quarter/eighth sample, bi-pred,
  weighted), deblocking, SAO (band and edge), at 8 and 10 bits (samples are
  Ints, so one code path with `bitDepth` works).
- Tiles and WPP (entropy_coding_sync) must decode correctly (single-
  threaded is fine: just handle the CABAC context save/restore and entry
  points). Range extensions, SCC, multi-layer: refuse with a warning.
- Output Pictures with `depth` 8 or 10 (the render module converts 10-bit
  already), `pts` reordered with the picture, `key`, SAR, matrix, range.
- Damage never stops the program: conceal, warn, continue.

## Tests and references

- Make fixtures with ffmpeg's libx265 from the shell (8-bit and 10-bit:
  `-pix_fmt yuv420p10le`; B-frames, SAO on/off, weighted prediction,
  tiles, WPP (`-x265-params wpp=1`), CRA open GOP, lossless/transform-skip
  if cheap, small odd sizes with cropping, 4:0:0) into
  `tests/hevc/fixtures/` (small) with `ffmpeg -f framemd5` references
  (`-pix_fmt` kept native; for 10-bit, framemd5 hashes 16-bit little-endian
  samples, which is what `core.pictureBytes` produces for depth > 8 — check
  that they agree). The shared fixture `tests/fixtures/hevc.mp4` too.
- Download the JCT-VC HEVC_v1 conformance bitstreams (zip files with
  `.bit`/`.bin` and `_yuv.md5`) from
  https://www.itu.int/wftp3/av-arch/jctvc-site/bitstream_exchange/draft_conformance/HEVC_v1/
  into `build/conformance/hevc/` and decode every Main/Main10 one you can;
  list which pass (the test skips them when absent).
- Be bit-exact everywhere (md5 per picture).

## Speed

This is decisive: movies are 1080p, often 10-bit, at 24 fps (42 ms a
picture). Print `time hevc 1080p 8-bit: N ms per picture` and the same for
10-bit on a 1080p clip made with x265 `-preset medium` at a movie-like
bitrate (~4–6 Mb/s). Design for speed from the first line (see BRIEF facts:
no allocation in hot loops, reuse scratch lists on the decoder, flat Int
lists, tables as module `let`s, CABAC as a tight method). The player will
also decode independent GOPs in parallel (each IDR/CRA starts a run on its
own decoder), so make sure `reset()` + decoding from any IRAP picture works
and that a decoder's state stays plain data.

The H.264 builder (module `h264/`, still finishing) solved many of the
same problems (CABAC engine, DPB, MC with padded planes, deblocking): you
may read `h264/` for ideas, but don't import it or edit it.

## Report

When done, reply with: API, features, which fixtures/conformance streams
pass bit-exact, per-picture timings (8-bit and 10-bit 1080p), known gaps,
anything added to NEEDED.md / TESSEL_ISSUES.md.
