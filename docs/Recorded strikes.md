# Hilda’s recorded strikes

The six normal-speed takes below come from the owner’s privately held video of Hilda. Each row pairs a distinct audio transient with a visible typebar excursion in the surrounding frames. The camera moves and the keys are partly obscured, so the app shares these takes across printing keys. The video averages 29.9 frames per second. Use the audio for millisecond timing and the picture to identify the action.

| App take | Audio transient window | Visible motion near the transient |
| --- | --- | --- |
| 01 | 29.470–29.475 s | A bar travels diagonally across the basket as the operator works the keys. |
| 02 | 30.100–30.105 s | With the print guide near the center of frame, the raised diagonal bar returns to the basket. |
| 03 | 31.350–31.355 s | A near-center bar is extended at 31.33 s and rebounds in the following frames. |
| 04 | 32.765–32.770 s | A right-of-center bar crosses the fan toward the guide, then returns. |
| 05 | 35.525–35.530 s | A left-of-center bar reaches the guide and drops back as the ribbon settles. |
| 06 | 37.785–37.790 s | A near-center bar returns just as the ribbon guide descends. |

The [extractor](../Source/hilda/build_hilda_audio.py) downmixes the phone’s stereo track to a mono point source, high-passes at 90 Hz, trims around the first strong rise and retains roughly a quarter-second of decay. A short end fade and modest gain matching keep noise and level changes between cuts under control. Each take also has faster and slower decays. Both preserve the first 45 ms sample-for-sample and use pitch-preserving time stretching for the tail.

At contact, [HildaAudio.gd](../GodivaStudio/machines/hilda/HildaAudio.gd) plays the event’s selected take at the ribbon/platen contact point. The current camera is the listener. The shared mixer rotates the stereo perspective, adjusts gain and allocates overlapping voices. Strike power controls level, and the same motion profile that drives the typebar selects the corresponding tempo. A shuffled bag uses all six normal takes before cycling. The chosen take is stored on the strike event. Service actions such as the spacebar need separately identified recordings.

[Listen to the six takes](<Recorded strokes.mp3>). This audition was captured from Godot’s master bus with Hilda’s 3D playback module active. The six actions play in source order at deliberate, ordinary and quick tempos.
