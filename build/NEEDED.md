xml/ ready (net builder, 2026-10-26): import "../xml"; xml.parse(text) / xml.parseData(bytes) -> Result<xml.Node>; Node.name/attributes/elements/text/tail, child(name), children(name), attr(name), childText(name), innerText, find(name); xml.element(...) + Node.toText(indent:declaration:) to write.
# Requests for changes to the shared contract (core/, testkit/, demux/api.tsl)


## aac: testkit.mediaFromRef gives wrong bytes for Matroska packets
For MKV/WebM, ffprobe's packet `pos` is the start of the SimpleBlock/Block
body (track number vint, 2-byte timecode, flags), not of the frame: e.g.
multi.mkv's first AAC packet is at pos 22762 but its frame starts at
22766 (`82 00 00 80` before it). `mediaFromRef` uses `pos` as the frame
offset, so decoders get 4 header bytes plus a frame cut 4 bytes short.
Suggested fix: when `ref.format` starts with "matroska", skip the block
header (vint length of the track number + 3 bytes) in `mediaFromRef`.
(Laced blocks would need more; the fixtures don't lace audio.) The aac test
works around it by skipping the header itself.

## subs: same Matroska `pos` issue (+1 to the aac request above)
subs_srt.mkv / subs_ass.mkv subtitle packets also start 4 bytes after
ffprobe's `pos`; tests/subs adds 4 to the offsets of subtitle packets itself.

## opus: same Matroska `pos` issue (+1 to the aac request above)
vp9.webm's and multi.mkv's Opus packets start 4 bytes after ffprobe's `pos`;
tests/opus skips the block header itself (vint track number + 3 bytes).

## demux-b: colour for video tracks; demux-a: Track.layout (+ colr)
**Lead:** done. `core.Track` now has `matrix: ColorMatrix = .unknown`,
`fullRange: Bool = false` and `layout: [String] = []` (defaults keep all
existing code working).

## demux-b note
Matroska "webvtt" packets are the whole block ("cue id\nsettings\ntext");
the subs decoder should split off the first two lines.

## audio-a: testkit.mediaFromRef offsets for Matroska are 4 bytes early
ffprobe's packet `pos` for MKV/WebM points at the start of the Block (track
number vint, 2-byte timecode, flags), not at the frame, so packets made by
`testkit.mediaFromRef` from an .mkv start with those bytes and miss the
frame's last bytes (seen on h264_high.mkv's mp3 track: pos 49311, frame
sync at 49315). Every decoder test that reads MKV packets through testkit is
affected (aac/opus/vorbis/h264 in mkv). Suggested fix in testkit (or
make_ref.py): for format "matroska,webm", add the Block header size
(1 + 3 for track numbers < 127) to `pos`. tests/mpa works around it by
adding 4 itself.

## mpeg4: mpeg4.avi.v.yuv starts with the first picture twice
ffmpeg's first decoded picture of mpeg4.avi has pts 1, so the rawvideo dump
(constant frame rate by default) repeats it to fill pts 0: the .v.yuv's
pictures 0 and 1 are the same and the rest are one late. Suggested fix in
tools/make_fixtures.sh: add `-fps_mode passthrough` to the `.v.yuv`
command (other fixtures with B-frames in AVI may have the same shift).
tests/mpeg4 drops the duplicate itself when pictures 0 and 1 are equal.

## mpeg4: the container's codec tag (fourcc) would help
ffmpeg picks the Xvid IDCT for "XVID"-tagged AVIs without user data, and
a few DivX/Xvid bug workarounds depend on the tag. A `Track.tag: String`
(AVI biCompression / MP4 sample entry / MKV CodecID) would let the decoder
do the same; meanwhile it relies on the user data strings only.

## dts: demux.sniff doesn't know .dtshd files or core-less DTS-HD streams
`.dtshd` files start with the chunk name "DTSHDHDR" (not a sync word) and
core-less DTS-HD streams with the substream sync 64 58 20 25, so
`demux.open` fails on them ("isn't a kind of media file"). Suggested
change in demux/api.tsl `sniff`: return "dts" when the first 8 bytes are
"DTSHDHDR" or the first 4 are 64 58 20 25, and map the extensions "dtshd"
(and "cpt") to "dts". `dtsOpen` already reads both (tests/dts calls
`demux.dtsOpen` directly for .dtshd meanwhile).

## dts: WAV and MPEG-TS DTS tracks
- demux/wav.tsl: format tag 0x2001 (WAVE_FORMAT_DTS) gives
  "unknown:wav2001"; it should be codec "dts" (tests/dts/fixtures/s51.wav,
  made by FFmpeg). DTS CD rips are also stored as plain PCM WAV (tag 1)
  holding a 14-bit DTS stream; FFmpeg detects them by finding the DTS sync
  (1F FF E8 00 07 Fx or FF 1F 00 E8 Fx 07) in the data. The dts decoder
  accepts packets that don't follow frame boundaries (partial frames carry
  over), so WAV's fixed-size blocks can be passed straight through.
- demux/ts.tsl: FFmpeg-made TS (stream type 0x82) works. FATE's dts.ts
  (build/conformance/dts/dts.ts) has DTS in stream type 0x06 without
  descriptors; FFmpeg finds it by the payload's DTS sync word. Also worth
  mapping: 0x85/0x86 (DTS-HD in Blu-ray M2TS), and 0x06 with a
  registration descriptor "DTS1"/"DTS2"/"DTS3" or the DVB DTS descriptor
  0x7B. Packets for DTS-HD in M2TS: one core frame + its substream (the
  PES payloads as they come are fine: the decoder resynchronises).

## hevc: testkit.mediaFromRef(skipBlockHeaders: true) cuts 4 bytes off every Matroska frame
ffprobe's `pos` for MKV points at the Block body, but its `size` is the
frame's own size (e.g. hevc10.mkv: pos 2984, size 3679, and the frame's 4-byte
length prefix says 3675 + 4). `skipBlockHeaders` moves the offset past the
header (right) and also does `p.size -= len + 3` (wrong), so each frame loses
its last 4 bytes. Suggested fix: drop the size adjustment. tests/hevc skips
the header itself (offset only) meanwhile.
**dts:** done (lead asked dts to do them): sniffing by the lead; WAV 0x2001
and DTS-in-PCM-WAV, TS 0x82/0x85/0x86 + descriptors 0x73/0x7B + type 0x06
payload sniffing with DTS frame cutting, by dts in demux/wav.tsl and
demux/ts.tsl.

## vp9: `mediaFromRef(skipBlockHeaders: true)` also cuts the end of each frame
With `skipBlockHeaders: true` the packet's offset moves past the Matroska
block header, but its size is lowered by the same amount — and ffprobe's
`size` is already the frame's own size, so the frame loses its last
(len + 3) bytes. For VP9 that damages the last tokens of every frame (in
vp9.webm, the last 4x4 V block of the first picture came out wrong).
Fix: keep `p.size` when moving `p.offset` in testkit.mediaFromRef.
tests/vp9 slices `file[pos + 4 ..< pos + 4 + size]` itself meanwhile.

## vp9: a `core.Chroma.yuv440`
VP9 profiles 1 and 3 allow 4:4:0 (chroma halved vertically only), which
`core.Chroma` can't describe. The vp9 decoder shows such frames as
`.yuv444` with every chroma row repeated (a copy per picture); a
`.yuv440` case (chromaWidth = width, chromaHeight = (height + 1) / 2, and
pictureBytes/render support) would avoid the copy. Rare in practice.

## dolby: demux.sniff misses two kinds of raw TrueHD stream (demux/api.tsl)
1. A raw stream that doesn't start on an access unit (FATE's
   lossless-audio/truehd_5.1.raw, any cut .thd) isn't recognised: sniff
   only looks for the major sync at offset 4. Suggested: when nothing else
   matched, look for F8 72 6F BA/BB in the first 64 KB and return "thd"
   (thdOpen skips to the first major sync itself); `truehd.thdFindMajorSync`
   does the search.
2. A Blu-ray ".thd+ac3" stream starts with an AC-3 frame, so sniff says
   "ac3" before it looks at the name. Suggested: for the extensions thd,
   mlp (and names ending .thd+ac3), return "thd" even when it starts with
   0B 77; thdOpen splits the AC-3 frames off as a second "ac3" track.
tests/truehd calls demux.thdOpen directly for those meanwhile.

## dolby: TrueHD tracks in MP4 and M2TS have no rate/channels (demux/mp4.tsl, demux/ts.tsl)
`mlpa` tracks from MP4 come with sampleRate 0, and TS stream type 0x83
tracks with neither rate nor channels; MKV's are set. The truehd decoder
sets rate/channels/layout after its first access unit, so playback works,
but the media info window and the player's setup would like them up
front: `truehd.thdReadMajorSync(firstPacket, 4)` (when the packet starts
with a major sync; otherwise `truehd.thdFindMajorSync`) gives
`group1Rate`, `mask` (→ `truehd.thdPopCount`, `truehd.thdLayoutNames`)
and `group1Bits`. Also for the info window: `truehd.streamInfo(track,
firstUnit:)` and `ac3.streamInfo(track, firstPacket:)` read the first
packet's bytes (Atmos, the dependent substream's 7.1). Bonus not done
(ts.tsl isn't mine): M2TS stream type 0x83 carrying an AC-3 core could be
split into its own "ac3" track; the truehd decoder skips interleaved AC-3
frames meanwhile.

## wma: `core.Track.blockAlign` (WAVEFORMATEX nBlockAlign) for WMA tracks
WMA 1/2/Pro/Lossless packets are blocks of nBlockAlign bytes, and a
container packet often holds several (e.g. a 16384-byte ASF media object
of eight 2048-byte WMA Pro blocks); the decoders can't find the block
size from the bitstream. Suggested: `blockAlign: Int = 0` in `core.Track`,
set from WAVEFORMATEX by demux/asf.tsl, avi.tsl (AviStream.blockAlign),
mkv.tsl (`mkvWaveFormat`: `d.uint16(at: 12)`) and wav.tsl. WMA 1/2 also
need the bitrate (nAvgBytesPerSec × 8: their frame layout depends on it):
asf/avi set `Track.bitrate`, but mkvWaveFormat doesn't yet. Meanwhile
`wma.newDecoder(track, blockAlign:)` takes it, and without it the decoder
takes the first packet's size (right for single-block packets).
**wma:** done by the lead (Track.blockAlign); demux/asf.tsl sets it.

## pro: MP4/MOV `Track.tag` = the sample entry's fourcc
`demux/mp4.tsl` maps `apch`/`ap4h`/`AVdh`… to "prores"/"dnxhd" but leaves
`Track.tag` empty. ffmpeg picks ProRes output depth from the tag (`ap4h`,
`ap4x` → 12-bit, the 422 tags → 10-bit), and the profile names in
`prores.streamInfo` need it too. Workaround in prores/: no tag → 4:4:4
frames are decoded at 12 bits, 4:2:2 at 10 (right for every real file
seen). Suggested: `t.tag = t.fourcc` for every sample entry (MKV could
put CodecID there; V_PRORES's CodecPrivate fourcc is used when tag is empty).

## pro: an RGB form for `core.Picture` (DNxHR 444 without colour transform)
DNxHR 444 / DNxHD 1256 frames without the ACT flag are RGB; ffmpeg outputs
them as gbrp10/12. `dnxhd` puts G, B, R in `y`, `u`, `v` (bit-exact with
ffmpeg's framemd5) and sets `Decoder.rgb`, but the Picture itself can't
say so, so the renderer would treat them as Y'CbCr. Suggested: a
`ColorMatrix.rgb` (identity; planes G, B, R as ffmpeg's gbrp), handled by
render.toRgba.

## pro: MOV clean aperture (`clap`) cropping
ffmpeg crops pictures by the MOV `clap` box (FATE prores4444_with_
transparency.mov shows 1888×1062 of its 1920×1080). Track has no crop
fields, so Reel shows the whole coded picture. Suggested: Track
`cropLeft/Top/Right/Bottom` from `clap` (demux-a), applied by the player
or renderer. (Decoders are compared with `-apply_cropping none` refs.)

## wmv (MS builder): demux/mkv.tsl doesn't name `V_MPEG4/MS/V3`
ffmpeg's Matroska muxer (and mkvmerge) write MS-MPEG4 v3 / DivX 3 as CodecID
`V_MPEG4/MS/V3` (not V_MS/VFW/FOURCC), which mkvOpen turns into
`unknown:V_MPEG4/MS/V3`, so wmv.newDecoder refuses the track. Suggested fix:
map `V_MPEG4/MS/V3` → "msmpeg4v3" (extra stays empty). tests/wmv uses AVI
copies of the v3 clips meanwhile (build/scratch/wmv/ms/remux.sh).

## vfx: decoders should set `Picture.interlaced` / `topFieldFirst`
vfx's deinterlacer (and `vfx.Chain` with `autoDeinterlace`, the default)
only touches pictures marked `interlaced`, but no decoder sets the flag yet
(grep: only dnxhd keeps its own `interlaced`, mpeg12/mpeg4/prores read a
field order into their own state). Suggested: mpeg12 `interlaced =
!progressive_frame` (picture coding extension) and `topFieldFirst =
top_field_first`; h264 `interlaced` for field pairs / MBAFF frames (and
pic_struct 3/4 from picture timing SEI), field order from the POCs of the
two fields; hevc from the field-indication / pic timing SEI; mpeg4 from the
VOL `interlaced` flag + VOP `top_field_first`; dnxhd/prores from their
frame headers. Until then the player can offer "deinterlace always"
(`Settings.autoDeinterlace = false`).

## net: mp4 — an fMP4 init's edit list with segment_duration 0 drops every fragment sample
HLS fMP4 init segments from ffmpeg (`-hls_segment_type fmp4`) carry
`elst` = [empty edit of 80 ticks, media edit with segment_duration 0].
In a fragmented file a 0 duration means the length isn't known yet
(ISO/IEC 14496-12 §8.6.6), but mp4Finish takes the sum of the durations
(80) as the edit's end and cuts every sample after it, so
`demux.open(init + fragment)` gives the tracks and 0 packets
(tests/net/fixtures/hls_fmp4/init.mp4 + s0.m4s). Suggested fix: in
mp4ParseElst/mp4Finish, a media edit with duration 0 (or a file with
mvex) means "no end": skip the cut. net works around it by patching such
durations in the init bytes (net/stream.tsl streamFixInit).

## net: ts — a transport stream of fewer than 5 packets isn't recognised
tsFindLayout wants 5 sync bytes in a row, so a short HLS segment (ffmpeg's
last audio-only segment, tests/net/fixtures/hls_alt/sEnglish_3.ts, 3
packets) fails with "no packet sync". Suggested fix: accept fewer packets
when the data is a whole number of 188-byte packets all starting with
0x47. net pads such segments with null packets (net/stream.tsl
streamPadTs).

## net: (FYI, not blocking) TS audio-only PES times differ from ffmpeg's
For an audio-only TS (tests/net/fixtures/hls_alt/sEnglish_0.ts), ffprobe
gives the first two AAC frames the same pts (1.458667) and then skips
1.80 s; tsOpen spaces every frame by 1024 samples from the PES pts. Reel's
looks more right; tests/net allows two frames of difference there.

## ui-prefs: settings the Preferences window shows that library.Preferences lacks
The Preferences view keeps these in `ui.PrefsExtra` (ui/prefs_model.tsl, a
plain struct the app holds in state and may save as JSON) until they're in
`library.Preferences` (and `validated`). Suggested fields, same names and
defaults:
- `speedStep: Float = 0.1` — Faster/Slower step (clamp 0.05…0.5).
- `sleepTimerMinutes: Int = 0` — sleep timer default; 0 off, −1 end of item.
- `miniPlayer: String = "off"` — "off" / "menu" / "small" (also when the
  window is made narrow).
- `alwaysShowControls: Bool = false` — never hide the controls over video.
- `volumeLimit: Float = 1.0` — highest volume (clamp 0.25…2.0; >1 boosts).
- `defaultAspect: String = "Default"` — a name of `render.aspectPresets`.
- `secondarySubtitleStyle: SubtitleStyle = SubtitleStyle(fontScale: 0.85,
  position: "top")` — the look of the second subtitle track.
Also: SubtitleStyle's `outlineWidth` has no unit in its comment; the view
treats it as pixels at 576 lines (2.0 = subs' default outline), see
`ui.prefsTextStyle`. When the fields move, PreferencesView's `extra:`
parameter goes away (the lead's wiring changes in one place).

## ui-tools: a public "can MP4 hold this track" in export/
ExportClipView greys out tracks the MP4 writer would leave out, but that
knowledge is private (`exSampleEntry` in export/mp4.tsl). ui/tools_export.tsl
`mp4Carries(track)` copies the list from mp4.tsl's header (h264, hevc,
av1 with av1C, vp9, mpeg4/2/1, mjpeg; aac, mp3/mp2/mp1, ac3, eac3, opus,
flac with STREAMINFO, alac with its cookie; tx3g/srt/text/webvtt).
Suggested: `public fn mp4Supports(_ t: core.Track) -> Bool` (or the reason
string) in export/, so the UI follows the writer when codecs are added.
