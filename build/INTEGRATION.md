# Notes for round 2 (player engine), from builders' reports

- vorbis: decoder returns whole blocks; trim the end to the last granule
  (container's last packet duration) in the player. First packet only
  primes (returns nothing). delay is always 0. Extras: tags, bitrate,
  parseComments, pictureFromComment, streamInfo, blockInfo/packetBlockSize
  (Ogg timing), splitHeaders/joinHeaders.
- subs: PGS/DVD bitmap cues come with end = subs.openEnd and an id, then
  again with the real end: keep cues with subs.replaceCues (decodeTrack
  does it). Default SRT size is libass's 16/288 of video height (small on
  small videos): use draw(scale:). Extras: loadFile(path) (any encoding,
  .sup too), parseVobSub(idx:sub:track:), decodeTrack(file, media, track:).
- render: keep one render.Renderer per video track (reuses buffers; plain
  toRgba is ~2 ms slower). Stretcher holds back up to 60 ms: use its
  `latency` for A/V sync. Mixer look-ahead ~1.5 ms. fitSize includes SAR.
  JPEG chroma siting is centred but render assumes "left" (≤ ½ px off).
- opus: rate 48000, delay = pre-skip (drop those frames). flush() returns
  nothing. Empty packet = conceal one packet.
- mpeg12/jpeg: bit-exact vs ffmpeg on ARM (NEON IDCT matched). 1080p MPEG-2
  ~17–19 ms per picture; 720p MJPEG ~12 ms. jpeg.decodeImage + toRgbaPixels
  for cover art; exifOrientation.
- demux-b: Matroska webvtt packets are "id\nsettings\ntext" (subs must
  split). Matroska pts already subtract CodecDelay. Packet offsets point at
  frames (unlike ffprobe's pos).
- Tessel: building big lists costs ~2.4 ns/item; copying an existing list
  is a fast memcpy. Reuse buffers in the player's frame queue.
- aac: implicit HE-AAC sets `rate` only after the first decode (ffmpeg's
  behaviour) — the player must read rate/channels after decoding, not
  from newDecoder. delay 1024 (LC) / 2048 (SBR); MP4 edit lists already
  shift priming to negative pts, so don't trim twice. tools() for info.
- mpa: delay = encoder delay + 529 from the LAME tag; padding field too.
- core.Track.tag (fourcc/CodecID) added after round 1 at mpeg4's request:
  demuxers don't fill it yet (round 2: AVI/MP4/MKV should); mpeg4 uses it
  to pick the Xvid IDCT when there's no user data.
- mpeg4: pictures keep the macroblock-aligned stride. Each picture gets the
  smallest pending pts (works for AVI, which has decode order only).
