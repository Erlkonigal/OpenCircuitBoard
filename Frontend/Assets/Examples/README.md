# Hello, World! 5×8 character display

[Open the example project](HelloWorld5x8.ocb) in the OpenCircuitBoard **desktop app** with **Ctrl+O**. It uses the existing v2 archive format and ordinary editable circuit components.

## Run

1. Open `HelloWorld5x8.ocb`. The LED display is centered near board coordinate `(0, 0)`; the control circuit extends to the left.
2. Choose **2D** for the clearest view. Keep the pointer at the center of the canvas and scroll down to about **9%** zoom (approximately 18 wheel steps from the initial 50%). All eight display rows should be visible. Drag with the middle mouse button if needed.
3. Set **Ticks per second** to **16**, then click **Run circuit**. Leave MAX off.

The five-column, eight-row display repeats `H → e → l → l → o → , → space → W → o → r → l → d → ! → H`. Every character occupies eight simulation ticks, so 16 TPS gives half a second per character and a 6.5-second loop. The two adjacent `l` characters appear continuously for one second; the space is half a second with all pixels off. The first four ticks after starting or resetting are blank (0.25 seconds at 16 TPS).

Pause to inspect a glyph or advance using **Next tick**. **Reset simulation** restarts the sequence; **Back to design** returns to editable components. Speed is an editor setting and is not stored in the project archive. The example runs entirely through the native Rust simulation.

## Circuit

Each display pixel is one independent LED component made of a 4×4 cell square. Pixel top-left coordinates are `(-22 + 10 × column, -37 + 10 × row)` for columns 0–4 and rows 0–7. The spacing leaves room for the five nested leads below each row.

The circuit below the large routing matrix, from left to right, contains:

- A ring of one Not and 103 Buffer gates. The inversion travels one stage per tick.
- Twelve XOR gates and one XNOR gate that decode the ring into thirteen repeating, eight-tick character slots. Both complementary half-cycles produce the same text sequence.
- Forty OR gates forming a fixed glyph ROM, one gate per output pixel. Each gate combines the character slots that illuminate its pixel.
- An initially enabled Latch and two Buffer stages that mask startup propagation.
- Forty AND gates combining the ROM outputs with startup enable, followed by the forty display LEDs. Every output has the same propagation depth.

Each matrix column belongs to a particular gate input or output. A trace junction connects its matching signal row; Cross cells carry every other intersection without joining its horizontal and vertical channels. Adjacent independent trace segments retain distinct component IDs. Press **F** to inspect the full circuit overview; zoom back into the rightmost display to read the text.

## Regenerate and validate

From the repository root, use native PowerShell on Windows or native Bash on Linux:

```text
make examples
make core-test
```

`make examples` builds the circuit from [the Rust generator](../../../Backend/Core/Examples/HelloWorld5x8.rs), checks every pixel at every tick for three complete loops, and writes `HelloWorld5x8.ocb`. It uses only the locked workspace dependencies. Edit the generator's `Message` and `glyph` table to customize the thirteen-character sequence; the current phase decoder has thirteen slots.

Core tests load the checked-in archive, compare it with generated data, replay the sequence, and check reference glyphs, reset, snapshot restoration and archive round trips. The desktop regression opens this same file and samples the actual WebGL canvas for `H`, comma, space, `W`, `!`, and the return to `H`. Its captures are written under root `build/` as `DesktopHelloWorld*Capture.png`.
