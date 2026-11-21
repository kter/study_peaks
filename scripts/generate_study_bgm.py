"""Render the original Study Peaks loops with NumPy and FFmpeg."""

import subprocess
from pathlib import Path

import numpy as np

RATE = 32_000
DESTINATION = (
    Path(__file__).resolve().parents[1] / "android/app/src/main/assets/study_bgm"
)
RNG = np.random.default_rng(621)


def tone(note, duration, voice):
    time = np.arange(round(duration * RATE), dtype=np.float32) / RATE
    phase = 2 * np.pi * 440 * 2 ** ((note - 69) / 12) * time
    if voice == "box":
        signal = np.sin(phase) + 0.32 * np.sin(2.76 * phase) * np.exp(-3 * time)
        envelope = np.minimum(1, time / 0.009) * np.exp(-3.2 * time)
    elif voice == "piano":
        signal = (
            np.sin(phase)
            + 0.44 * np.sin(2.004 * phase) * np.exp(-1.6 * time)
            + 0.24 * np.sin(3.016 * phase) * np.exp(-3.8 * time)
            + 0.09 * np.sin(5.055 * phase) * np.exp(-6 * time)
        )
        envelope = np.minimum(1, time / 0.012) * np.exp(-1.7 * time)
    elif voice == "strings":
        vibrato = 0.32 * np.sin(2 * np.pi * 4.7 * time)
        signal = sum(
            0.5**index
            * np.sin(
                harmonic * (phase + vibrato)
                + 0.14 * np.sin(phase * 0.005 * harmonic)
            )
            for index, harmonic in enumerate((1, 2, 3, 4, 5))
        )
        signal += 0.35 * np.sin(phase * 1.0025 - vibrato)
        envelope = np.minimum(1, time / 0.8) ** 1.4
    elif voice == "pad":
        signal = (
            np.sin(phase)
            + 0.55 * np.sin(phase * 1.003 + 0.8)
            + 0.18 * np.sin(phase * 2.001 + 2.1)
        )
        envelope = np.minimum(1, time / 1.1) ** 1.4
        envelope *= 0.82 + 0.18 * np.sin(time * 2.4)
    elif voice == "keys":
        signal = np.sin(phase + 0.48 * np.exp(-3.4 * time) * np.sin(phase * 2))
        signal += 0.18 * np.sin(phase * 2.002) * np.exp(-2 * time)
        envelope = np.minimum(1, time / 0.03) * np.exp(-1.3 * time)
    else:  # plucked bass
        signal = np.sin(phase) + 0.24 * np.sin(phase * 2) * np.exp(-8 * time)
        envelope = np.minimum(1, time / 0.017) * np.exp(-2.5 * time)
    release = 0.65 if voice in ("pad", "strings") else 0.24
    return signal * envelope * np.minimum(1, time[::-1] / release)


def drum(kind):
    time = np.arange(round(RATE * 0.22)) / RATE
    if kind == "kick":
        signal = np.sin(2 * np.pi * (44 * time + 1.0 * (1 - np.exp(-50 * time))))
        return signal * np.exp(-19 * time) * np.minimum(1, time / 0.006)
    noise = RNG.normal(size=len(time))
    signal = np.diff(noise, prepend=noise[0])
    decay = 45 if kind == "brush" else 95
    return signal * np.exp(-decay * time) * np.minimum(1, time / 0.01)


# Each progression is an original cycle. Pitches are MIDI note numbers.
SCORES = {
    "music_box": (
        72,
        [(48, 60, 64, 67, 71), (45, 60, 64, 67, 69),
         (41, 57, 60, 65, 69), (43, 59, 62, 67, 69),
         (48, 60, 64, 67, 72), (50, 62, 65, 69, 72),
         (41, 60, 65, 69, 72), (43, 59, 62, 67, 71)],
    ),
    "dreamy": (
        60,
        [(50, 57, 60, 64, 65), (46, 57, 60, 62, 65),
         (41, 57, 60, 64, 67), (48, 55, 62, 64, 67),
         (50, 57, 60, 65, 69), (45, 55, 60, 64, 69),
         (46, 57, 60, 62, 65), (48, 55, 60, 62, 67)],
    ),
    "piano": (
        66,
        [(43, 55, 59, 62, 66), (47, 54, 57, 62, 66),
         (40, 55, 59, 62, 64), (48, 55, 60, 64, 67),
         (45, 57, 60, 64, 67), (50, 57, 60, 64, 66),
         (43, 55, 59, 62, 64), (48, 55, 60, 64, 67)],
    ),
    "orchestra": (
        58,
        [(45, 57, 60, 64, 71), (41, 57, 60, 64, 69),
         (48, 55, 60, 64, 67), (43, 55, 59, 62, 69),
         (45, 57, 60, 64, 72), (48, 55, 60, 64, 71),
         (41, 57, 60, 65, 69), (43, 55, 60, 62, 67)],
    ),
    "lo_fi": (
        74,
        [(46, 57, 60, 62, 65), (45, 55, 59, 60, 64),
         (38, 53, 57, 60, 64), (43, 53, 57, 58, 62),
         (46, 57, 60, 62, 65), (40, 53, 57, 59, 62),
         (45, 55, 60, 62, 64), (41, 55, 57, 60, 64)],
    ),
    "jazz": (
        87,
        [(41, 57, 60, 64, 67), (38, 53, 57, 60, 65),
         (43, 58, 62, 65, 69), (48, 58, 62, 64, 69),
         (45, 55, 59, 60, 64), (38, 54, 57, 60, 64),
         (43, 58, 62, 65, 67), (48, 58, 62, 64, 67)],
    ),
}


def music(name):
    bpm, chords = SCORES[name]
    beat = 60 / bpm
    bars = 24
    loop = np.zeros((round(bars * 4 * beat * RATE), 2), dtype=np.float32)

    def mix(signal, bar, position, level, pan=0):
        start = round((bar * 4 + position) * beat * RATE) % len(loop)
        gains = level * np.sqrt(np.array([(1 - pan) / 2, (1 + pan) / 2]))
        first = min(len(signal), len(loop) - start)
        loop[start:start + first] += signal[:first, None] * gains
        loop[:len(signal) - first] += signal[first:, None] * gains

    def note(pitch, voice, bar, position, length, level, pan=0):
        mix(tone(pitch, length * beat, voice), bar, position, level, pan)

    for bar in range(bars):
        root, third, fifth, seventh, top = chords[bar % len(chords)]
        passage = bar // len(chords)
        if name == "music_box":
            notes = (third, fifth, top, seventh, fifth, top)
            for index, position in enumerate((0, 0.5, 1.25, 2, 2.75, 3.5)):
                pitch = notes[(index + passage) % len(notes)]
                note(pitch + 12, "box", bar, position, 1.6,
                     0.12 if index % 3 == 0 else 0.085, (-1)**index * 0.28)
            note(root + 12, "box", bar, 0, 2.5, 0.075, -0.25)
        elif name in ("dreamy", "orchestra"):
            voice = "pad" if name == "dreamy" else "strings"
            pitches = (root, third, fifth, seventh)
            for index, pitch in enumerate(pitches):
                note(pitch, voice, bar, -0.35 + 0.09 * index, 4.75,
                     0.081 if index < 3 else 0.051, (index - 1.5) * 0.27)
            if (bar + passage) % 4 != 3:
                note(top + 12, voice, bar, 1.1, 2.8, 0.038, 0.18)
        elif name == "piano":
            for index, (position, pitch) in enumerate(
                zip((0, 0.75, 1.5, 2, 2.75, 3.5),
                    (root, fifth, third, seventh, fifth, third))
            ):
                note(pitch, "piano", bar, position, 2.2,
                     0.14 if index == 0 else 0.075, -0.3)
            melody = (top + 12, seventh + 12, fifth + 12)
            note(melody[(bar + passage) % len(melody)], "piano",
                 bar, 1.25, 2.3, 0.14, 0.25)
            if bar % 2 == 0:
                note(top + 12, "piano", bar, 3.1, 1.5, 0.09, 0.2)
        else:
            swing = 2 / 3 if name == "jazz" else 0.54
            bass_ticks = (0, 1, 2, 3) if name == "jazz" else (0, 2 + swing)
            bass = (root - 12, root - 5, root, root - 5)
            for position, pitch in zip(bass_ticks, bass):
                note(pitch, "bass", bar, position, 1.25, 0.23)
            for position in (swing, 2 + swing):
                for index, pitch in enumerate((third, fifth, seventh, top)):
                    note(pitch, "keys", bar, position + index * 0.018,
                         1.75, 0.095 - index * 0.009, 0.28)
            melody = (top + 12, seventh + 12, fifth + 12, top + 12)
            if (bar + passage) % 4 != 3:
                note(melody[(bar + passage) % len(melody)], "keys",
                     bar, 1 + swing, 1.1, 0.12, -0.19)
            for position in (1, 3):
                mix(drum("brush"), bar, position, 0.018, 0.25)
            for position in (0, 1 + swing, 2, 3 + swing):
                mix(drum("hat"), bar, position, 0.009, -0.3)
            for position in (0, 2):
                mix(drum("kick"), bar, position, 0.11 if name == "lo_fi" else 0.035)

    # Wrap the room reflections around the boundary as well as the music.
    dry = loop.copy()
    for delay, gain in ((0.072, 0.14), (0.123, 0.10), (0.193, 0.06)):
        loop += gain * np.roll(dry[:, ::-1], round(RATE * delay), axis=0)
    return loop


def noise_loop(seconds, slope, low, high):
    frames = seconds * RATE
    hz = np.fft.rfftfreq(frames, 1 / RATE)
    # Spectral shaping also makes the loop periodic with no padded silence.
    color = np.maximum(hz, low) ** slope
    color *= (hz / np.sqrt(hz**2 + low**2)) ** 2
    color /= np.sqrt(1 + (hz / high) ** 4)
    signal = np.fft.irfft(np.fft.rfft(RNG.normal(size=frames)) * color, n=frames)
    return (signal / np.std(signal)).astype(np.float32)


def ambience(name):
    seconds = 72
    if name == "brown_noise":
        noise = noise_loop(seconds, -1, 40, 1800)
        return np.column_stack((noise, noise))
    common = noise_loop(seconds, -0.6, 115, 3400)
    sides = np.column_stack(
        [noise_loop(seconds, -0.12, 600, 6300) for _ in range(2)]
    )
    if name == "rain":
        return 0.62 * common[:, None] + 0.38 * sides
    time = np.arange(len(common)) / RATE
    tide = ((1 + np.sin(2 * np.pi * (8 * time / seconds + 0.12))) / 2) ** 2
    foam = 0.13 + 0.87 * tide
    foam *= 0.85 + 0.15 * np.cos(2 * np.pi * 3 * time / seconds)
    undertow = noise_loop(seconds, -0.95, 65, 1400) * (0.65 + 0.35 * tide)
    return 0.60 * foam[:, None] * (common[:, None] + 0.54 * sides) + 0.38 * undertow[:, None]


def encode(name, signal):
    rms = np.sqrt(np.mean(signal**2))
    gain = min(0.075 / rms, 0.81 / np.max(np.abs(signal)))
    pcm = (signal * gain).astype("<f4")
    subprocess.run(
        [
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            "-f", "f32le", "-ar", str(RATE), "-ac", str(signal.shape[1]), "-i", "-",
            "-c:a", "libvorbis", "-q:a", "2", str(DESTINATION / f"{name}.ogg"),
        ],
        input=pcm.tobytes(),
        check=True,
    )


def main():
    DESTINATION.mkdir(parents=True, exist_ok=True)
    for name in (*SCORES, "rain", "waves", "brown_noise"):
        encode(name, music(name) if name in SCORES else ambience(name))


if __name__ == "__main__":
    main()
