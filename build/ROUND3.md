# Reel — round 3 builders: VP9 and DTS

Read `build/BRIEF.md` first: every rule there applies (Tessel docs only from
`build/tessel-docs/`, own files only, author/date headers, tests ending
`<name>: N of M passed`, Tessel problems to `build/TESSEL_ISSUES.md`, no git,
no loose pkill, ffmpeg only from scripts/shell as a reference). Its "Facts
about this Tessel" section matters; `build/TESSEL_ISSUES.md` lists more speed
traps found since (module-level `let` lists are slow to read — copy to a
local; re-passing `bind` parameters is slow; building big lists is slow —
reuse buffers). The finished decoders (`h264/`, `mpeg12/`, `aac/`, `ac3/`)
are good examples to read; don't edit or import them.

The player decodes in Tessel `background` jobs (no shared memory between
threads). To use two cores for one video stream it runs two stages side by
side: a **parser** (entropy decoding into plain per-block arrays) and a
**reconstructor** (prediction, transforms, filters, output). Video decoders
are built as those two plain-data structs plus the ordinary Decoder that
chains them.

## vp9: module `vp9/` — test `tests/vp9`

Only touch `vp9/`, `tests/vp9/`, `build/scratch/vp9/`,
`build/conformance/vp9/`.

A bit-exact VP9 decoder (the VP9 bitstream spec v0.6/0.7), **profiles 0
and 2** (4:2:0, 8 and 10 bit; profile 1/3 (4:4:4, 4:2:2) if cheap after
that):

```text
public struct Decoder { … plain data … }
public fn newDecoder(_ track: core.Track) -> Result<Decoder>
  fn decode(_ packet: Data, pts: Int, dts: Int, key: Bool) -> [core.Picture]
  fn flush() -> [core.Picture]
  fn reset()
  skipNonReference: Bool      // skip frames with refresh_frame_flags == 0
  warnings: [String]
public struct Parser, public struct Reconstructor, public struct ParsedFrame,
public fn newPipeline(_ track: core.Track) -> Result<…>   // see above
public fn streamInfo(_ track: core.Track) -> String  // "VP9 Profile 2, 1920×1080, 10-bit"
```

- Packets are whole frames as WebM/MKV/MP4/IVF store them: superframes
  (several frames + index in one packet; hidden alt-ref frames output
  nothing, `show_existing_frame` repeats one), uncompressed and compressed
  headers, bool decoder, probability adaptation (forward updates and
  backward adaptation after each frame), segmentation, loop filter (levels,
  deltas, all filter sizes), quantisation, tiles (columns and rows; decode
  single-threaded), intra (all modes, edge availability), inter (8-tap
  regular/smooth/sharp and bilinear, compound prediction, scaled reference
  frames when frame sizes change), MV prediction and reference MV lists,
  transforms DCT/ADST 4–32 and WHT for lossless, frame size changes
  (`refresh` with different sizes), intra-only frames, error resilient mode.
- Output `core.Picture` with `depth` 8 or 10, `pts` of the packet that showed
  it, `key`, `matrix` from color_space (BT.601/709/2020), full range flag.
  VP9 has no reordering: frames come out in order.
- Fixtures: `tests/fixtures/vp9.webm` (+ its framemd5). Make more with
  ffmpeg's libvpx-vp9 (8-bit, `-pix_fmt yuv420p10le -profile:v 2` 10-bit,
  tiles `-tile-columns 2`, `-row-mt 1`, alt-ref frames `-auto-alt-ref 1
  -lag-in-frames 25`, lossless `-lossless 1`, resolution changes via
  ffmpeg concat of two sizes, odd sizes) with framemd5 references; download
  the libvpx test vectors (vp90-2-*.webm and their .md5, e.g. from
  https://storage.googleapis.com/downloads.webmproject.org/test_data/libvpx/)
  into `build/conformance/vp9/` and list which pass. Bit-exact everywhere.
- Speed: print per-picture parse and reconstruct times for 720p and 1080p,
  8-bit and 10-bit (make movie-like clips: `-b:v 3M`). Goal: max(parse,
  reconstruct) ≤ 30 ms at 1080p 8-bit.
- Damage never stops the program.

## dts: module `dts/` plus `demux/dts.tsl` — test `tests/dts`

Only touch `dts/`, `demux/dts.tsl` (replace the stub; `demux/api.tsl`
already sniffs DTS and calls `dtsOpen`), `tests/dts/`, `build/scratch/dts/`,
`build/conformance/dts/`. Prefix private names in `demux/dts.tsl` with `dts`.

A DTS decoder with the audio decoder API of the brief:

```text
public struct Decoder { rate, channels, layout, delay, warnings … }
public fn newDecoder(_ track: core.Track) -> Result<Decoder>   // codec "dts"
  fn decode(_ packet: Data, pts: Int) -> core.Samples
  fn flush() -> core.Samples
  fn reset()
public fn frameInfo(_ data: Data, at: Int) -> …   // sync, size, rate, channels
public fn streamInfo(_ track: core.Track) -> String  // "DTS-HD MA 7.1, 48 kHz, 24-bit"
```

Order of work, each bit-exact or ≥ 90 dB vs ffmpeg before moving on:
1. **DTS core** (Coherent Acoustics, ETSI TS 102 114): all four sync forms
   (16-bit BE/LE, 14-bit BE/LE as on CDs/WAV), frame header, subframes,
   subband samples (ADPCM prediction, VQ, joint intensity, all Huffman
   codebooks), scale factors, transient modes, the 32-band QMF (both filter
   banks), LFE interpolation, dynamic range (off), downmix not needed:
   output every channel in WAV order (5.1 = FL FR FC LFE BL BR or SL SR per
   the speaker layout). ffmpeg decodes the core in float: aim ≥ 90 dB.
2. **XCh** (6.1 extension) and **X96** (96 kHz) if streams exist.
3. **DTS-HD**: substream headers (sync 0x64582025); **XLL** (DTS-HD Master
   Audio lossless): bit-exact lossless output at 24/16 bit, up to 7.1,
   channel sets, residual, fixed and adaptive predictors, balance/decimator
   stages as ffmpeg's dca_xll.c supports; **XBR/XXCH** (High Resolution) as
   far as ffmpeg supports them. Most Blu-ray rips are DTS-HD MA: this is
   the valuable part, so get there.
4. **`demux/dts.tsl` `dtsOpen`**: raw .dts / .dtshd (strip the DTSHDHDR
   chunk container of .dtshd files), frame sync with validation of the
   next frame, packets = one core frame plus its HD substream, rate,
   channels, duration from frame count.
- Fixtures: ffmpeg's `dca` encoder (`-c:a dca -strict -2`) makes core
  streams (stereo, 5.1, various bitrates) into WAV/raw/MKV; references with
  ffmpeg as f32. ffmpeg can't encode DTS-HD: download sample files (the
  FATE suite has `dts/` and `dca/` samples incl. XLL:
  https://fate-suite.ffmpeg.org/dts/ and /dca/) into
  `build/conformance/dts/` and produce references with ffmpeg; keep small
  cuts as committed fixtures (a few hundred KB).
- Also check DTS inside MKV, TS and MP4 fixtures you make with ffmpeg
  (`-c:a copy` of a core stream) through `demux.open`.
- Speed: print × real time for 5.1 core and for XLL 7.1.

## Report

When done, reply with: API, features, which fixtures/conformance streams
pass (bit-exact or SNR), timings, known gaps, anything added to
NEEDED.md / TESSEL_ISSUES.md.
