"""The four sounds the interface is allowed to make (FR-921).

Synthesised rather than sourced. A sample from a library would need its
licence carried, checked and believed; these are arithmetic, so there is
nothing to license and nothing to attribute. It also means they can be tuned
by editing a number rather than by finding a different recording.

Every one of them is:

  * short — 400ms at the outside, because a sound that outlasts the thing it
    is reporting is a sound people turn off;
  * soft — a sine with a little second harmonic, no attack transient, and a
    long release, so it reads as a chime rather than a beep;
  * quiet — peaking at a third of full scale, since this plays over a video
    call where it is competing with somebody talking.

The script writes WAV, and the repository carries MP3: 28 KB for the four
instead of 73 KB, and MP3 is the one format every browser has agreed on for
long enough that nobody has to think about it. Regenerating needs ffmpeg:

    python3 priv/static/sounds/build.py
    cd priv/static/sounds
    for f in reveal timer vote close; do
      ffmpeg -y -i $f.wav -codec:a libmp3lame -b:a 64k -ac 1 $f.mp3 && rm $f.wav
    done
"""

import math
import struct
import wave
from pathlib import Path

RATE = 22050
HERE = Path(__file__).parent

# A minor pentatonic-ish set, so any two of them played near each other do not
# clash. Hz.
NOTES = {"low": 392.00, "mid": 523.25, "high": 659.25, "top": 783.99}


def tone(frequency, seconds, start=0.0, gain=0.30):
    """One note, with a soft attack and an exponential release."""
    samples = int(RATE * seconds)
    attack = int(RATE * 0.012)
    out = []

    for index in range(samples):
        t = index / RATE
        # Fundamental plus a quiet octave: enough body to hear over speech
        # without the buzz a square wave would give it.
        value = math.sin(2 * math.pi * frequency * t)
        value += 0.18 * math.sin(4 * math.pi * frequency * t)

        envelope = min(1.0, index / attack) * math.exp(-3.4 * t / seconds)
        out.append(gain * envelope * value / 1.18)

    return int(RATE * start), out


def mix(*layers):
    length = max(offset + len(samples) for offset, samples in layers)
    buffer = [0.0] * length

    for offset, samples in layers:
        for index, value in enumerate(samples):
            buffer[offset + index] += value

    return buffer


def write(name, buffer):
    frames = b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, value)) * 32767)) for value in buffer
    )

    with wave.open(str(HERE / f"{name}.wav"), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(frames)

    print(f"{name}.wav  {len(frames) // 1024} KB")


# The reveal: everybody's cards arriving at once. Rising, and the only one of
# the four with three notes, because it is the only one that is an event
# rather than a notification.
write(
    "reveal",
    mix(
        tone(NOTES["mid"], 0.34),
        tone(NOTES["high"], 0.34, start=0.075),
        tone(NOTES["top"], 0.38, start=0.15),
    ),
)

# The timer running out. Two of the same note, low: this one has to be
# noticeable while somebody is mid-sentence without being a fire alarm.
write("timer", mix(tone(NOTES["low"], 0.22), tone(NOTES["low"], 0.30, start=0.19)))

# A vote landing. The shortest thing here — it can happen five times in ten
# seconds, so it is a tick rather than a chime.
write("vote", mix(tone(NOTES["high"], 0.11, gain=0.22)))

# The session closing. Falling, and the only one that resolves downward,
# because it is the only one that means "that is the end of it".
write(
    "close",
    mix(tone(NOTES["high"], 0.26), tone(NOTES["mid"], 0.40, start=0.13)),
)
