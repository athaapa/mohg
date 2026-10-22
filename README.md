# mohg

A simple polyphonic synthesizer for macOS written in Odin.

i started by getting a sine wave to play through `AudioToolbox`, then used
`CoreMIDI` to connect my MIDI keyboard. from there i've been adding synth
features and investigating how much work happens in the render callback.

i wrote up the performance investigation here:
[mohg: Building and profiling a real-time synthesizer](https://athapa.dev/systems/performance/audio/2026/10/22/mohg.html)

## results

with 16 unison oscillators per voice, this is how many voices fit before the
mean render time crosses the 1.33 ms budget (offline benchmark, Apple M4):

| oversampling | first oversampled version | now |
| --- | ---: | ---: |
| 1x | ~119 | ~117 |
| 2x | ~67 | ~78 |
| 4x | ~35 | ~59 |

at 4x, 32 voices went from 1209.89 µs to about 670 µs per block. most of that
came from caching per-note oscillator values, replacing `tanh` with a rational
approximation, and only computing the decimator outputs i keep. i also added
heavier saturation, drift, and noise along the way, which is why 1x barely moved.

![voice-count sweep](docs/final-voice-sweep.png)

individual blocks still go over budget in bursts, even well under capacity.
that's the main open question, and the writeup goes through what i've ruled out.

## building

you'll need macOS, Odin, and Apple's Clang/macOS SDK from Xcode or the Command
Line Tools. i'm using Odin `dev-2026-09` on an Apple MacBook Air with an M4 chip.

connect a MIDI controller, then run from the repo root:

```sh
mkdir -p build
clang -fblocks -O2 -c src/core_midi_bridge.c -o build/core_midi_bridge.o
odin build src -o:speed -out:build/mohg
./build/mohg
```

the synth connects to the first MIDI source it can open and uses the default
audio output. play a note to hear it. press Enter to exit. keep the volume low
while experimenting with resonance and drive.

## synth features

- polyphony with oldest-voice stealing
- sine, square, saw, and triangle waves
- ADSR per voice
- up to 16 unison oscillators per voice, with detune and stereo panning
- polyBLEP for saw/square and polyBLAMP for triangle
- nonlinear ZDF ladder filter with saturation in each stage
- oversampling and FIR decimation
- oscillator drift, per-voice tuning/filter variation, and stereo chorus

the settings are in [src/main.odin](src/main.odin). i'm using an Arturia MiniLab 3
as my MIDI keyboard. i mapped its knobs to CC 74 for cutoff, 71 for resonance,
and 76 for drive.

## how it works

each voice has its own envelope, oscillators, and left/right filters. the synth
adds the voices together to produce an interleaved stereo buffer. if the user
plays more than `max_voices`, it takes the oldest voice and assigns it the new
note.

the MIDI callback and audio callback run on different threads. i use a
fixed-capacity SPSC queue to pass note and control events to the audio thread,
which applies them between blocks. the voice pool and oscillator arrays are
fixed-size too.

i also added a telemetry queue so i can observe voice events while playing.
the audio thread writes a record, and another thread reads and prints it. if
that queue fills up, it drops the record and counts the drop.
