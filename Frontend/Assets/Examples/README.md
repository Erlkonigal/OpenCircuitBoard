# Editable memory examples

Open the `.ocb` archives in the desktop app with Ctrl+O. Both use formatVersion 2 with `circuitModel: "booleanSwitch"`, ordinary editable cells, and binary 0/1 signals. Previous-model archives are rejected.

## Hello, World! 5x8 display

[HelloWorld5x8.ocb](HelloWorld5x8.ocb) repeats `H -> e -> l -> l -> o -> , -> space -> W -> o -> r -> l -> d -> !`.

1. Open the archive. The LED display is near `(0, 0)`; the control circuit extends left.
2. Choose **2D**. Keep the pointer at the canvas center and scroll out to about **9%** (18 wheel steps from the initial 50%). All eight rows should be visible.
3. Set **Ticks per second** to **16**, leave MAX off, and run.

Each character lasts eight ticks: half a second at 16 TPS, with a 6.5-second loop. The first five ticks are blank; H appears at tick 5. Pause and step to inspect individual ticks. Reset restarts the sequence; Back to design restores editable cells.

The circuit contains a 104-stage Not/Buffer ring, thirteen XOR/XNOR phase outputs, a 13-word by 40-bit ROM matrix, startup masking and forty LEDs. Each ROM bit line defaults to 1. A stored zero places a Switch between the bit line and a Trace fixed at 0; the word line controls that Switch. Selecting a word grounds its zero bits. Stored ones need no switch. Fixed 0 suppresses an undriven default 1; switches do not add data delay after closing.

Five output Buses each carry the eight rows of a display column. Colored Trace taps connect directly to the directional AND and LED pins. Cross keeps intersecting word and bit lines isolated. Pixel top-lefts are `(-21 + 10 * column, -37 + 10 * row)`, each a 4x4 LED component. One startup Latch and three Buffer stages mask propagation before the first glyph.

| Layout metric | Previous circuit | Switch ROM |
| --- | ---: | ---: |
| Occupied cells | 50,310 | 27,315 |
| Board rectangle | 538x188 | 525x237 |
| Rectangle area | 101,144 | 124,425 |

Occupied cells decrease **45.7%**, while rectangle area increases **23.0%**. These measure different aspects of compression. Press F for the full overview and zoom into the rightmost display for readable glyphs.

## RAM 16x8

[Ram16x8.ocb](Ram16x8.ocb) stores sixteen eight-bit words using pairs of NOR gates with feedback. Each row decodes a four-bit address. A read Switch connects each cell's Q output to its bit line; write gates set or clear the feedback cell from that same bit line. Eight external data Switches connect the input Latches to the shared bit lines when Drive is asserted. OE enables the selected read row; WE enables writes. Reset clears every cell and masks reads and writes while asserted.

The board is **384x483**, with **98,916 occupied cells**. This example demonstrates shared read/write wiring; there is no previous RAM layout for a compression comparison.

The top control bank is at **y = -212**. Latches are clickable during simulation. Bit 0 is the least significant bit.

| Control | Board x coordinate | Component ID | Initial state |
| --- | --- | --- | --- |
| Address bits 0-3 | -300, -296, -292, -288 | 9-12 | 0 |
| OE | -284 | 13 | 0 |
| WE | -280 | 14 | 0 |
| Reset | -276 | 15 | 1 |
| Drive | -272 | 16 | 0 |
| Data input bits 0-7 | -268, -264, -260, -256, -252, -248, -244, -240 | 17-24 | 0 |
| Read LEDs, bits 0-7 | -229, -219, -209, -199, -189, -179, -169, -159 | 60001-60008 | 0 |

Bus colors 0-7 carry the shared data bit lines. A second Bus carries address, OE, WE, Reset and Drive; a third carries the eight data input Latches. Address decoding and storage use ordinary gates. No dedicated decoder, enable, diode, tri-state, or memory Ink is required.

Use **8 ticks per settling stage** for this circuit. Set Step length to 8 and pause between stages. The Reset Latch starts at 1 so the NOR feedback cells receive a definite clear before access.

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

Core tests compare the committed archives with their generators and verify timing, reset and archive round trips. Browser tests cover directional pins, rotation/history, source/default controls, Cross joins and previews in both display modes. Native tests read actual rendered ROM glyphs and exercise RAM reads/writes/reset/timeline through the real Tauri simulation worker. Captures are generated under root `build/`, including `DesktopHelloWorld*Capture.png`, `DesktopRamSharedBusCapture.png`, `Switch*Capture.png`, `TraceSourceSettingsCapture.png` and `CrossJoinSettingsCapture.png`.
