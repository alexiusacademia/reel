# Tessel problems found while building Reel


## render: no fast way to make a big list (slow, not wrong)
What: making a list of n items costs ~2.4 ns an item whichever way:
`append` in a loop, `prefix`/`slice` of a bigger list, `Data.bytes` (3.4 ns),
`map`, `+`. Copying a whole existing list (copy-on-write, then one write) is
a memcpy, ~0.25–0.6 ms for 2M Ints. There is no `[Int](repeating:count:)`.
A 1920×1080 RGBA output list therefore costs ~5 ms to build (the whole
budget for a picture is 12 ms). Also each `list[i] = v` store runs a
uniqueness + bounds check (~1 ns), so fills are memory-op bound.
Repro: build/scratch/render/issue_list_alloc/main.tsl (append ~5 ms, copy
~0.5 ms, prefix ~5.5 ms for 2,073,600 Ints).
Workaround (render/video.tsl): `render.Renderer` keeps its output list
between pictures (a reused list costs one memcpy when the caller still holds
the previous one); the first output is made by copying a plane of the right
size (the Y plane for same-size output) and trimming; scratch planes are
copies of a chroma plane instead of `core.zeros`.

## mpeg12: same slow list building (+1 to the render note above)
What: `slice`/`prefix` of 3M Ints take ~11 ms and `appendAll` ~14 ms,
while `a + []` or a copy-on-write copy of a whole list take ~1.5 ms.
Copying three planes out of one big frame pool with `slice` cost 7.5 ms of
a 23 ms 1080p MPEG-2 picture.
Repro: build/scratch/mpeg12/repro_slice/main.tsl.
Workaround (mpeg12/decoder.tsl, engine.tsl): each frame keeps its own Y,
Cb, Cr lists, which pictures share; the decoder's next write to a list a
picture still holds is one fast copy-on-write copy (picture now 17 ms).

## demux-b (and others): `tessel check <module folder>` reports "no entry point"
`tessel check demux` from ~/Dev/reel prints "error: this program has no
entry point" among the real errors, so a module never checks clean.
Workaround: check a test program that imports the module.

## aac: `tessel check <module folder>` needs a main
`tessel check aac` (a module folder with no `fn main`) fails with "add an
`app` … or a `fn main()`", so a module can't be type-checked on its own as
the brief suggests. Workaround: `tessel check tests/aac` (the test program
that imports the module) checks it in ~0.04 s. Not a bug in the docs'
sense (start_cli says "check a program"), just a mismatch with the brief.

## h264: passing a `bind` parameter on to another function is slow (~11 ns per call)
- What: inside a function with `_ e: bind E`, calling `g(e)` where `g` also
  takes `bind E` costs about 11 ns per call (10M calls: ~120 ms), versus
  ~0.8 ns for `g(e)` from a local `var`, and ~0.4 ns for a method call
  `e.m()`. Element access through such a re-bound list parameter is also
  about 2x slower than from a method on `self`.
- Repro: build/scratch/h264/repro-rebind (`tessel build … && ./r`).
- Workaround (h264): the decoder's per-macroblock code is written as
  methods of its engine struct (calls between methods are cheap); leaf
  sample functions take lists by `bind` from those methods only.

## mpeg4: `bind` list parameters are slow inside big functions (slow, not wrong)
What: passing a struct's list fields to a function as `bind` parameters
(e.g. `idct(self.blk, self.curY, …)`) makes every element access inside a
larger function an indirect call to a small "address of field" stub
(`ldr x8,[x0,#0x20]; add x0,x8,#off; ret`, seen in `sample` profiles at
~20% of decode time). A tight 1-line loop gets optimised, so the cost only
shows in real code. The same IDCT as a method of the struct that owns the
lists runs ~1.6× faster.
Repro: build/scratch/mpeg4/t3/main.tsl (200k IDCTs: bind 73 ms, method
46 ms); build/scratch/mpeg4/t2/main.tsl is the simple loop that doesn't
show it.
Workaround (mpeg4/pics.tsl): the pictures and scratch lists live in one
struct (`M4Pics`) whose methods do motion compensation and the IDCTs on
their own fields; 640×480 decoding went from 10 ms to 5.2 ms a picture.

## h264: reading a module-level `let` list is ~5× slower than a local copy

- What: indexing a module-level `let table: [Int] = [...]` inside a loop
  costs ~2.1 ns per read; the same reads through `let t = table` (a local)
  cost ~0.4 ns (Tessel 0.15.0, macOS arm64, release build).
- Repro: build/scratch/h264/repro-global (`tessel build build/scratch/h264/repro-global -o r && ./r`).
- Workaround (h264): h264NewEng copies the module tables into fields of
  the decoder state (Eng) once; hot code reads the fields.

## h264: `data[i] = v` on a Data compiles, then crashes at run time
- What: assigning a byte of a `Data` (`var d = Data(bytes: [0, 0]); d[0] = 1`)
  passes `tessel build`, and the program stops with "the program crashed
  (invalid memory access); this is a bug in Tessel". The docs say bytes
  can't be changed one at a time, so this should be a compile error.
- Repro: build/scratch/h264/repro-databind.
- Workaround: none needed in h264 (planes stay `[Int]`); found while
  trying `Data` planes to save memory.

## h264: a background job's round trip costs about 5–6 ms, whatever the work
- What: `await background { … }` for work that takes 0, 1 or 5 ms returns
  after about 6 ms; for 20 ms of work, after about 24.7 ms (Tessel 0.15.0,
  macOS, command-line program). Two jobs do run on two cores at once.
- Repro: build/scratch/h264/bgtest (`tessel build build/scratch/h264/bgtest -o r && ./r`).
- Matters for the H.264 pipeline: about 5 ms of each picture's wall time
  at 1080p is this wait (see h264/pipeline.tsl), so handing a job two
  pictures at a time would hide half of it.

## hevc: `wrappingAdd` / `wrappingMultiply` are ~3× slower than `+` / `*` (slow, not wrong)
What: an 8-tap filter written with `a.wrappingMultiply(b)` / `s.wrappingAdd(t)`
runs at ~7.2 ns per output sample, the same filter with the checked `*` and
`+` at ~2.5 ns (Tessel 0.15.0, M5 Pro, `tessel build`). The wrapping methods
look like real calls rather than inlined instructions, so they can't be used
to skip overflow checks in hot loops.
Repro: build/scratch/hevc/probe2/main.tsl (`tessel build build/scratch/hevc/probe2
-o p && ./p`: "checked", "wrapping", "sliding", "swar" lines).
Workaround (hevc/recon.tsl): checked arithmetic, with two samples packed in
one Int (a + b << 32, both halves far from overflow) so each multiply-add
does two samples' work; interpolation went from 22 to 15 ms per 1080p picture.

## hevc: built programs have no symbols, so a sampling profiler can't help
What: `sample <pid>` on a `tessel build` binary shows only `???` addresses
for program code (`nm` lists ~750 runtime symbols, none of the program's
functions), also with `TESSEL_LINKER=system`. Not a bug in the docs' sense;
a `--symbols` (or keeping function names in release builds) would make
performance work much easier.
Workaround: timing with `now()` around stages and per operation kind.

## dts: long list literals compile slowly (slow, not wrong)
What: a module-level `let big: [Int] = [ … ]` literal's build time grows
faster than linearly with its length: 2,000 items 0.35 s, 4,000 0.8 s,
8,000 2.3 s; a 50,000-item literal didn't finish in 2 minutes.
Repro: build/scratch/dts/biglist/main.tsl, the 8,000-item case
(`tessel build build/scratch/dts/biglist -o t`).
Workaround (dts/bigtables.tsl): big tables (the 32,768-entry VQ codebook,
ADPCM coefficients, filter windows) are base64 text unpacked with
`decodeBase64` when the program starts (builds in ~1 s, unpacking < 1 ms).

## vp9: assigning `[]` to a list field costs an allocation (~20 ns) (slow, not wrong)
What: moving a big list out of a struct field with `a = b; b = []` costs
about 20 ns per `= []` (a new empty list is allocated each time), while
swapping two fields through a local (`let t = a; a = c; c = t`) costs ~4 ns
and allocates nothing. In a decoder that moved each plane into its pixel
engine and back per block (take/give with `= []`), this was ~6 allocations
per block.
Repro: build/scratch/vp9/emptylist/main.tsl (`tessel build
build/scratch/vp9/emptylist -o r && ./r`: 48 ns vs 8 ns per pair).
Workaround (vp9/pixel.tsl `use`/`swapPlane`): the three planes live in the
pixel engine's fields for the whole frame and the working one is swapped
into `pl` through a local.

## Playback smoothness findings (2026-10-25, Tessel 0.15.0)

- `playSound` on macOS makes an AVPlayer that loads the file
  asynchronously, so a new sound starts a moment after the call; there is
  no "prepare" call or ready signal (only `duration() > 0`). Reel works
  around it by starting the next chunk muted and paused ahead of time.
- `playSound` does nothing in a program without an `app` (duration 0,
  position never moves), so sound timing can't be measured from a CLI.
- `g.image(pixels:)` hashes every pixel on every draw to see whether the
  picture changed (1.5 M pixels for 1080p), and every timer firing rebuilds
  the whole view tree and redraws the window. A 100 Hz timer therefore
  costs a full rebuild and redraw 100 times a second; Reel now redraws its
  picture canvas only when the frame changes.
- Headless scripts run on a virtual clock (`now()` jumps with `wait`), so a
  script can't show real-time playback lag.

## pro: a small scratch list in a hot method is ~3× slower than locals (slow, not wrong)
What: an 8×8 IDCT whose row pass writes 64 intermediates to a `[Int]`
field (`tmp[t + k] = …`) and whose column pass reads them back ran at
~330 ns a block; the same code with the 64 intermediates in local `var`s
(generated, unrolled) runs at ~90 ns. Also, in a table-driven entropy
loop, working out the next state as `min(run, 15) * 10 + min(level, 9)`
then a lookup cost ~4 ns per symbol more than storing the next state's
offset in the table entry itself (the loop is latency-bound).
Repro: build/scratch/pro/ib/main.tsl (`tessel build build/scratch/pro/ib
-o r && ./r`) times the unrolled version (~90 ns plus filling); the
earlier list version was the same arithmetic with `tmp` as a 64-item
list field.
Workaround (prores/, dnxhd/): IDCTs generated by tests/prores/genidct.py
with locals; entropy tables carry the next state.

## net: no way to read an HTTP response as it arrives (internet radio)
What: `request` calls `done` only when the body has ended, so an endless
Icecast/SHOUTcast stream never returns (measured: nothing after 2 s while
the server keeps sending). `download` does write the body to "<to>.part"
as it arrives, and `readData` of the .part works while it grows (16 KB/s
in, 16 KB/s readable), so Reel plays radio by polling the .part — but
each poll re-reads the whole file, and `download` can't send request
headers, so "Icy-MetaData: 1" can't be asked for and in-stream song
titles never come (Reel polls the server's status pages instead). Also
the response headers (icy-name, icy-metaint, content-type) of a download
aren't visible. Minor: after `cancelRequest` of a download the .part is
removed a moment later, not at once (exists right after, gone 2 s later).
Would help: `download(… headers:)` and a `onData: fn(Data)` /
`onHeaders` callback for `request` (like openWebSocket's onData), or a
ranged `readData(path, from:, to:)` (issue #45).
Repro: build/scratch/net/probe (needs tests/net/server.py; steps in the
file's header), build/scratch/net/cancel.
Workaround (net/radio.tsl): `net.Radio.take(readData(path + ".part"))`
every 0.5 s; restart the download now and then and join the new one with
`net.spliceOffset` (servers send a burst of recent audio on connect).

## net: `request` follows redirects without telling the final URL
What: a 302 comes back as the target's 206/200 with no Location and no
final URL, so relative URIs in a redirected playlist resolve against the
URL asked for, not the one served (players resolve against the final
URL, RFC 8216 §4.1 / RFC 3986 §5.1.3). `file://` requests ignore a Range
header (status 200, whole file), which is as documented. Repro:
build/scratch/net/probe ("redirect:" line). Workaround: none needed for
same-folder redirects; a `finalUrl` field on HttpResponse would fix it.

## ui-fx: Toggle, Picker and TextField have no onChange (gap, not a bug)
What: Slider, Stepper and ColorPicker take an `onChange` block, but
`Toggle`, `Picker` (all styles) and `TextField` don't, and `.onTap` on a
Toggle or Picker never runs (the control takes the click). A view that
edits a `bind` value therefore can't tell its caller "the user changed
something" when the change comes from a switch or a picker, short of a
timer comparing values (which rebuilds the whole window each tick).
Repro: build/scratch/ui-fx/repro_toggle/main.tsl (`tessel build
build/scratch/ui-fx/repro_toggle -o r && TESSEL_SCRIPT='click "Switch";
click "B"; tree' ./r` prints "taps 0 on true pick b").
Workaround (ui/fx_controls.tsl): the Effects window's switches and
choice rows are made of Buttons (FxuSwitchButton, FxuSegments, and a
Button + popover list for long lists, FxuChoiceMenu), which call back;
text fields apply on `.onSubmit`. An `onChange:` on Toggle and Picker
(like Slider's) would let these be the native controls.

## ui-prefs: `.disabled` on a view whose body is a `GridRow` is dropped
What: in a `Grid`, `MyRow("Label") { Toggle(…) }.disabled(true)` (where
`view MyRow(…) { GridRow { … } }`) leaves the row enabled: `tree` shows no
`disabled` and a click still flips the toggle. The same `.disabled(true)`
on a `GridRow` written directly works. (The docs say a modifier on a custom
view applies to its whole body, and that a GridRow may come from a view.)
Repro: build/scratch/ui-prefs/repro-gridrow-disabled (`tessel build … -o r`,
`TESSEL_SCRIPT='click "A"; click "B"; tree' ./r`: A turns on, B stays off).
Workaround (ui/prefs_controls.tsl): `PrefsRow(_:off:)` takes the flag and
puts `.disabled` on the HStack inside the row.

## ui-prefs: Toggle, Picker and TextField have no `onChange` (gap, not a bug)
What: Slider, Stepper, ColorPicker, FontPicker and DatePicker take an
`onChange` block, but Toggle, Picker (all styles), TextField and
SearchField don't, so a settings view that must tell its caller "something
changed" (to save) can't do it from those controls without wrapping each.
Workaround (ui/prefs_controls.tsl `PrefsChangeWatch`): a hidden `Text` with
`.id(key)`, where `key` is `toJson` of the settings, appears again whenever
the settings change, and its `.onAppear` compares with the last key and
calls `onChange`. Probe: build/scratch/ui-prefs/onchange-watch.

## ui-tools: `scrollTo(row)` always scrolls the first LazyVStack in the window
What: with two `LazyVStack`s in one window, `scrollTo(80)` scrolls the first
one in the view tree; there's no way to scroll a row of the second into view
(its rows that aren't built have no `.id` to aim at with a String id).
Repro: build/scratch/ui-tools/repro-scrollto (`tessel build … -o r &&
TESSEL_SCRIPT='click "Left to 80"; tree' ./r`: left list built 59..92, the
right one can't be reached). Request: a way to name the list
(`scrollTo(80, in: "find")` or `LazyVStack(…).id("find")` scoping its rows).
Workaround (ui/tools_find.tsl): FindPanel and TranscriptPanel each scroll
their own LazyVStack by row number, so a window should show only one of
them at a time (and no other lazy list above it).

## ui-tools: a plain VStack of 300 small rows costs ~10 ms per rebuild (slow, not wrong)
What: a `Scroll { VStack { for i in 0..300 { row(i) } } }` (each row ~10
views) costs ~10 ms per rebuild; the same rows in a `LazyVStack` ~0.5 ms
(1,000 rebuilds from a 100 Hz `every` timer: 10.4 s vs 0.58 s). Since every
timer firing rebuilds the whole window, any list longer than a few dozen
rows in the player window must be lazy.
Repro: build/scratch/ui-tools/bench (`tessel build … -o b && LAZY=0
TESSEL_SCRIPT='wait 10' ./b`, then LAZY=1).

## ui-library: a `fn … -> View` with several views keeps only the last, silently
What: a function returning `View` whose body lists several views
(`Text("first")` then `Text("second")`) builds only the last one; no error
or warning. A `view` declaration with the same body shows both (and a
`view` made of MenuItems works as context-menu content, which the function
form silently cuts to its last item).
Repro: build/scratch/ui-library/issue_fnview/main.tsl (`tessel build
build/scratch/ui-library/issue_fnview -o r && TESSEL_SCRIPT=tree ./r` shows
only Text "second").
Workaround (ui/lib_*.tsl): functions returning View wrap their views in one
stack; menus are `view`s (LibItemMenu, ChapterMenuItems).
