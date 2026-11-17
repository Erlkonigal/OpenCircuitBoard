# Editable memory examples

Open the `.ocb` archives in the desktop app with Ctrl+O. Both use formatVersion 2 with `circuitModel: "booleanSwitch"`, ordinary editable cells, and binary 0/1 signals. Previous-model archives are rejected.

## Hello, World! 5x8 display

[HelloWorld5x8.ocb](HelloWorld5x8.ocb) repeats `H -> e -> l -> l -> o -> , -> space -> W -> o -> r -> l -> d -> !`.

1. Open the archive. The LED display is near `(0, 0)`; the control circuit extends left.
2. Choose **2D**. Keep the pointer at the canvas center and scroll out to about **9%** (18 wheel steps from the initial 50%). All eight rows should be visible.
3. Set **Ticks per second** to **16**, leave MAX off, and run.

Each character lasts eight ticks: half a second at 16 TPS, with a 6.5-second loop. The first thirteen ticks are blank; H appears at tick 13 while the sequencer initializes and the address decoder settles. Pause and step to inspect individual ticks. Reset restarts the sequence; Back to design restores editable cells.

The sequencer is a 13-stage one-hot shift ring. Each storage bit uses two phase-controlled Switches and a Buffer feedback path. Four OR gates encode the active stage as a four-bit address; one Bus carries those address bits and the valid signal to a decoder placed beside the ROM. The decoder's two local Buses select one of thirteen word lines. The valid signal masks the display while the ring starts. This replaces the long multi-signal sequencer-to-ROM route with a four-bit address Bus.

The 13-word by 40-bit ROM matrix uses Switches to select high bits. Each undriven bit line is 0. A stored one places a Switch between the bit line and a Trace driven by an On Button; the word line controls that Switch. Selecting a word connects its high bits. Stored zeros need no Switch. Closed Switches add no data delay.

Five output Buses each carry the eight rows of a display column. Colored Trace taps connect directly to the directional AND and LED pins. Cross keeps intersecting word and bit lines isolated. Pixel top-lefts are `(-21 + 10 * column, -37 + 10 * row)`, each a 4x4 LED component. Three Buffer stages delay the valid signal until startup settles.

The thirteen register stages now occupy two rows of compact master/slave cells. Each stage keeps its three feedback nets on a local Bus; four shared Buses carry the ring outputs, phases, address and startup signals. Single-cell two/three-input gates use their directional side pins. The encoder sits beside the stages instead of extending a single long control bank.

| Layout metric | Previous encoded ring | Compact register |
| --- | ---: | ---: |
| Occupied cells | 24,313 | 19,443 |
| Board rectangle | 575x242 | 343x240 |
| Board area | 139,150 | 82,320 |
| Actual occupied bounding rectangle | 567x234 | 335x232 |
| Register/control bounding rectangle | 561x43 | 278x41 |

The register/control region uses **52.8% less bounding area**. The complete circuit's actual bounding area drops **41.4%**, with **20.0% fewer occupied cells**. Both versions retain four cells of canvas padding, so these reductions come from the circuit layout. The display coordinates, LED sizes, startup and character timing are unchanged. Press F for the full overview and zoom into the rightmost display for readable glyphs.

## RAM 16x8

[Ram16x8.ocb](Ram16x8.ocb) stores sixteen eight-bit words using pairs of NOR gates with feedback. Each row decodes a four-bit address. A read Switch connects each cell's Q output to its bit line; write gates set or clear the feedback cell from that same bit line. Eight external data Switches connect the input Buttons to the shared bit lines when Drive is asserted. OE enables the selected read row; WE enables writes. Reset clears every cell and masks reads and writes while asserted.

The array is arranged as sixteen rows by eight columns of **12x16-cell storage units**. Each unit contains two single-cell AND gates, two single-cell NOR gates and a read Switch. Reset enters the Q NOR directly, replacing the separate clear OR. Data inversion is shared by each column, address inversion and the Reset inversion are shared by all rows. Bit lines run vertically; row read/write controls and Reset run horizontally through isolated Cross intersections. Each feedback loop closes inside its own unit.

| Layout metric | Previous RAM | Compact RAM |
| --- | ---: | ---: |
| Occupied cells | 98,916 | 20,432 |
| Board rectangle | 384x483 | 134x296 |
| Board area | 185,472 | 39,664 |
| Actual occupied bounding rectangle | 376x475 | 126x288 |

The actual bounding area drops **79.7%**, and occupied cells drop **79.3%**. Capacity, control IDs, reset behavior and eight-tick access stages are preserved.

The address/control Buttons are at **y = -146**. Data Buttons are at **y = -132**, and read LEDs at **y = -128**. Buttons are clickable during simulation. Bit 0 is the least significant bit.

| Control | Board x coordinate | Component ID | Initial state |
| --- | --- | --- | --- |
| Address bits 0-3 | -72, -69, -66, -63 | 9-12 | 0 |
| OE | -60 | 13 | 0 |
| WE | -57 | 14 | 0 |
| Reset | -54 | 15 | 1 |
| Drive | -51 | 16 | 0 |
| Data input bits 0-7 | -44, -32, -20, -8, 4, 16, 28, 40 | 17-24 | 0 |
| Read LEDs, bits 0-7 | -44, -32, -20, -8, 4, 16, 28, 40 | 60001-60008 | 0 |

Trace colors 0-7 carry the shared data bit lines and their independently routed inversions. A control Bus carries address, OE, WE, Reset and Drive; another carries the shared address/Reset inversions. Each row has a small local selection/read/write Bus. Address decoding and storage use ordinary gates. No dedicated decoder, enable, diode, tri-state, or memory Ink is required.

Use **8 ticks per settling stage** for this circuit. Set Step length to 8 and pause between stages. The Reset Button starts at 1 so the NOR feedback cells receive a definite clear before access.

Initialization:

1. Advance 8 ticks with Reset = 1 and OE = WE = Drive = 0.
2. Set Reset = 0 and advance 8 ticks.

Write:

1. Set OE = WE = 0 and wait 8 ticks before changing address or data.
2. Choose address and data, set Drive = 1, and wait 8 ticks.
3. Set WE = 1 and wait 8 ticks.
4. Set WE = 0 and wait 8 ticks; then set Drive = 0 and wait 8 ticks.

Read:

1. Keep WE = Drive = OE = 0 and wait 8 ticks before changing address.
2. Choose the address and wait 8 ticks.
3. Set OE = 1, wait 8 ticks, and read the eight LEDs.
4. Set OE = 0 and wait 8 ticks before changing address again.

Keep OE at 0 while changing the address: different decoder paths settle on different ticks, and connecting two rows can feed their OR-combined outputs back into storage. Keep WE at 0 and settled before changing address/data, and avoid overlapping Drive and OE. These stages provide the read/write isolation for this feedback-cell design.

To clear all words, set OE/WE/Drive to 0 and settle, assert Reset for 8 ticks, then release Reset and settle for 8 ticks.

## Regenerate and validate

From native PowerShell on Windows or native Bash on Linux:

```text
make examples
make core-test
make frontend-test
make native-test
```

The [ROM generator](../../../Backend/Core/Examples/HelloWorld5x8.rs) verifies every LED at every tick for three complete loops. The [RAM generator](../../../Backend/Core/Examples/Ram16x8.rs) writes every address with several byte patterns, reads them back, clears memory and checks snapshot restoration. `make examples` writes both archives using locked workspace dependencies.

Core tests compare the committed archives with their generators and verify timing, reset, archive round trips, walking-bit/row isolation, disabled-output release, long holds and reset write masking. Footprint regressions measure actual occupied bounds independently from canvas padding. Browser tests load both committed archives and capture compact overviews and storage details in 2D and 2.5D; they also cover icon rotation without input/output dots, history, source/default controls, Cross joins and previews in both display modes. Native tests read actual rendered ROM glyphs and exercise RAM reads/writes/reset/timeline through the real Tauri simulation worker. Captures are generated under root `build/`, including `HelloWorld5x8-*-OverviewCapture.png`, `Ram16x8-*-StorageCapture.png`, `DesktopHelloWorld*Capture.png`, `DesktopRamSharedBusCapture.png`, `DesktopRamCompactFlatCapture.png`, `Switch*Capture.png`, `TraceSourceSettingsCapture.png` and `CrossJoinSettingsCapture.png`.
