# Typewriter Emulator

I photographed what my Olympia SM9 De Luxe, Hilda, typed and recorded how her keys sounded. Those impressions and recordings are what you see and hear when you type on her in this emulator. You can also sit down at Godiva, my French Canadian Hermes 3000. Open either machine’s cover to watch the linkage behind a keystroke.

[Download the Windows release](https://github.com/ImperishableNEET/Typewriter-Emulator/releases/latest) · [MIT code license](LICENSE) · [Model and audio licenses](ASSETS.md)

![Hilda typing the quick brown fox pangram](docs/Emulated%20pangram.png)

## Run

Open `GodivaStudio/project.godot` with Godot **4.4.1** and press **F6** with the desk scene open, or **F5** to run the project. The project includes both runtime models and the imported source assets Godot needs. Initial import builds the local cache. Blender is optional.

Choose **Machines → Hilda**, then **Open cover** and **Type pangram**. You can type, click a cap, hold Shift for its other face, or open **Key guide**. The **Olympia layout** maps physical computer key positions to Hilda’s photographed caps. Ctrl+Alt+Shift with Q, H, T or P gives ¼, ½, ¾ or ¢. Godiva has her own bindings under **Machine controls**. Each desk keeps its mounted draft. Finished sheets can be read on both.

[Full Olympia keyboard proof](docs/Keyboard%20proof.png) · [Hilda’s recorded strikes](docs/Recorded%20strikes.md)

On Hilda, choose **View → Carriage close-up** for the return lever, spacing selector and platen knobs. Enter returns the carriage. The selector offers single, 1½, double and free settings. Turn either knob to move the sheet, or use Alt+Up/Down for a half-line adjustment.

To register a form between lines, Ctrl-drag Hilda’s left platen knob or drag it outward first and then turn it. Release it at the desired height. The next carriage return preserves that baseline offset. Right-click during the adjustment to cancel.

Use the paper rest control below Hilda’s desk to fold, raise, or extend the graduated support. The mounted sheet follows it as it rises. [Hilda’s revised ivory cover and extended paper rest](docs/Hilda%20paper%20support.png)

On either machine, **Ctrl+.** clears all tab stops, **Ctrl+=** sets a stop at the current column, and **Ctrl+-** clears that stop. Press **Tab** between entries to type aligned columns. You can also click Hilda’s **set** and **clear** keys beside the spacebar and her **TAB** key at the top right. [Hilda’s typed table](docs/Tab%20stop%20proof.png)

## Build and verify on Windows

Install Godot 4.4.1 and its matching Windows export templates. From the repository root in PowerShell, set `$godot` to the console executable.

```powershell
& $godot --headless --path GodivaStudio --import
& ./tools/Test-Source.ps1 -Godot $godot
New-Item -ItemType Directory -Force build | Out-Null
$exe = Join-Path (Resolve-Path build) 'Typewriter Emulator.exe'
& $godot --headless --path GodivaStudio --export-release 'Windows Desktop' $exe
& ./Baseline/Godiva/Verify.ps1 -Godot $godot -Executable $exe
& ./Baseline/Hilda/Verify.ps1 -Godot $godot -Executable $exe
& ./Baseline/TabStops/Verify.ps1 -Godot $godot -Executable $exe
```

Tests use a temporary Windows profile to protect mounted drafts. The optional Windows Wooting bridge can be compiled with MinGW using the command at the top of [wooting_touch.c](Source/wooting_touch.c). It uses the operator’s locally installed analog SDK. The default checkout uses simulated touch.

## Assets and edition differences

The public-source edition uses a synthesized Godiva backspace and authored timing defaults. Hilda uses six takes extracted from the owner’s recording. The public tree contains derived impressions, cropped proof images and machine sounds. The owner’s original photographs, raw phone video and research records stay in the authoring archive.

The [Blender builder](Source/hilda/build_hilda.py) generates Hilda’s editable scene and runtime GLB. To create both, run `blender --background --factory-startup --python-exit-code 1 --python Source/hilda/build_hilda.py` with Blender 5.0.1. The Godiva runtime uses `assets/machine.json` and `assets/machine.bin`. Her private editable scene contains embedded research and reference materials. The extraction scripts for Hilda document the optical and audio processing and require the original owner media to regenerate the shipped derivatives.

See [asset credits and rights](NOTICE.md) before redistribution.
