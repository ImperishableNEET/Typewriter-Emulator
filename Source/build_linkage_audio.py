"""Build the short linkage sounds for actions without identified isolated recordings.

Frequencies and timings are listening-design choices. The recorded typebar and bell
assets are cut separately from supersupernator's CC0 Hermes 3000 recording.
"""
import array
import math
from pathlib import Path
import random
import wave

RATE = 44100
DEST = Path(__file__).resolve().parents[1] / "GodivaStudio" / "assets" / "sounds"

# Each contact specifies time, relative energy, resonance scale, and decay scale.
CONTACTS = {
    "backspace": [(0, .42, .85, .9), (.010, .30, 1.55, .8), (.041, .19, 1.18, .8)],
    "tab": [(0, .32, .76, 1.2), (.014, .18, 1.78, .7), (.056, .51, .89, 1.1)],
    "jam": [(0, .42, 1.52, .8), (.005, .26, 1.86, .75), (.019, .17, .92, .9)],
    "miss": [(0, .25, .70, 1.2), (.024, .11, .81, .9)],
    "platen": [(0, .27, 1.30, .9), (.006, .15, .89, 1.)],

}


def build(name, contacts, take=1):
    stem = name + "_mechanism" if take == 1 else f"{name}_{take:02}"
    rng = random.Random("Godiva " + (name if take == 1 else stem))
    # Vary the individual contact strengths and the spacing between impacts.
    # The same metal parts keep their resonant frequencies across performances.
    if take > 1:
        contacts = [(time * rng.uniform(.86, 1.14), energy * rng.uniform(.84, 1.13),
                     scale, decay * rng.uniform(.88, 1.12)) for time, energy, scale, decay in contacts]
    frames = int((contacts[-1][0] + .16) * RATE)
    channels = [[0.] * frames for _ in range(2)]
    for t0, energy, scale, decay in contacts:
        samples = int(.15 * RATE)
        impulse = [rng.uniform(-1., 1.) for _ in range(samples)]
        for c, channel in enumerate(channels):
            start = int((t0 + c * .00009) * RATE)
            phase = 1. + c * .008
            previous = 0.
            for i in range(samples):
                t = i / RATE
                body = sum(gain * math.sin(math.tau * freq * scale * phase * t) *
                           math.exp(-t / (length * decay))
                           for freq, gain, length in [(234., .45, .018), (713., .22, .010),
                                                      (1519., .15, .006), (2940., .08, .005)])
                previous += .38 * (impulse[i] - previous)
                edge = (impulse[i] - previous) * math.exp(-t / (.0031 * decay))
                attack = min(1., i / 13)
                channel[start+i] += energy * attack * (body + .40 * edge)
    packed = array.array("h")
    for left, right in zip(*channels):
        packed.extend(round(max(-1., min(1., v)) * 32767) for v in (left, right))
    with wave.open(str(DEST / (stem + ".wav")), "wb") as wav:
        wav.setparams((2, 2, RATE, 0, "NONE", ""))
        wav.writeframes(packed.tobytes())


if __name__ == "__main__":
    DEST.mkdir(exist_ok=True)
    for name, contacts in CONTACTS.items():
        build(name, contacts)
        if name in {"tab", "jam", "miss"}:
            for take in range(2, 6):
                build(name, contacts, take)
