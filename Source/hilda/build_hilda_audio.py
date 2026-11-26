"""Cut observed typebar strokes from Hilda's owner recording. Requires ffmpeg."""
from array import array
from pathlib import Path
import math
import subprocess
import wave


ROOT = Path(__file__).resolve().parents[2]
VIDEO = ROOT / "References/Hilda/Originals/20261126_012310.mp4"
DEST = ROOT / "GodivaStudio/machines/hilda/audio"
RATE = 48000
# Dominant audio impulses, confirmed against adjacent frames of moving bars.
IMPULSES = (29.470, 30.100, 31.350, 32.765, 35.525, 37.785)


def decode(args, payload=None):
    proc = subprocess.run(
        ["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", *args,
         "-ac", "1", "-ar", str(RATE), "-f", "s16le", "pipe:1"],
        input=payload, capture_output=True, check=True,
    )
    return array("h", proc.stdout)


def write(path, samples):
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as output:
        output.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        output.writeframes(samples.tobytes())


def duration_variant(samples, speed):
    # Preserve the first attack unmodified. Crossfade a time-stretched decay
    # so the high-frequency metal click keeps the same pitch and arrival time.
    overlap = int(RATE * .006)
    join = int(RATE * .045)
    tail = decode(["-f", "s16le", "-ac", "1", "-ar", str(RATE), "-i", "pipe:0",
                   "-af", f"atempo={speed}"], samples[join:].tobytes())
    result = samples[:join]
    for i in range(overlap):
        mix = i / overlap
        result.append(round(samples[join+i] * (1-mix) + tail[i] * mix))
    result.extend(tail[overlap:])
    return result


def energy(samples):
    return sum(x*x for x in samples) / len(samples)


def main():
    source = decode(["-i", str(VIDEO), "-map", "0:a:0", "-af", "highpass=f=90"])
    for index, peak_time in enumerate(IMPULSES, 1):
        # Find the first strong rise leading to the observed impulse in 1 ms
        # windows. Exclude distant approach noise before the slug arrives.
        search = round((peak_time - .03) * RATE)
        windows = [energy(source[i:i+48]) for i in range(search, search+1920, 48)]
        threshold = max(windows) * .08
        rise = next(i for i, value in enumerate(windows) if value >= threshold)
        onset = search + rise*48 - 72
        samples = source[onset:onset + round(RATE * .245)]
        # Light level matching retains real differences between the takes.
        rms = math.sqrt(energy(samples[:round(RATE * .06)]))
        gain = min(1.35, max(.8, 2400/rms), 27500/max(map(abs,samples)))
        fade = round(.025 * RATE)
        for i, value in enumerate(samples):
            envelope = min(1, i/48, (len(samples)-1-i)/fade)
            samples[i] = round(value * gain * envelope)
        name = f"strike_{index:02d}"
        write(DEST / f"{name}.wav", samples)
        for label, speed in (("quick",1.17), ("deliberate",.86)):
            varied = duration_variant(samples, speed)
            write(DEST / "tempo" / f"{name}_{label}.wav", varied)
        print(f"{name}: start {onset/RATE:.4f} s, peak {peak_time:.3f} s")


if __name__ == "__main__":
    main()
