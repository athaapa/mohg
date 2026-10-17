# mohg

A simple polyphonic synthesizer for macOS written in Odin.

**WIP.** i'm building this to learn real-time audio and performance engineering.
the goal is to render within a 64-sample buffer at 48 kHz, which gives me about
1.33 ms to finish each block.

i started by getting a sine wave to play through `AudioToolbox`, then used
`CoreMIDI` to connect my MIDI keyboard. from there i've been adding synth
features and investigating how much work happens in the render callback.

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

## performance engineering

there are a few nested loops in `synth_render`: frames, oversampling, voices,
and oscillators. i use an offline benchmark that calls the same renderer to
figure out how much each part contributes.

after building the MIDI bridge above, build `bench`:

```sh
clang -O2 -g -c bench/signpost_bridge.c -o build/signpost_bridge.o
odin build bench -o:speed -debug -out:build/bench
build/bench --help
```

for render timings:

```sh
build/bench render --voices 32 --unison 16 --oversampling 4
```

this reports mean, p50, p99, and how many blocks exceeded the buffer budget.

to look at aliasing, i compare the rendered spectrum with an 8x-rate reference:

```sh
build/bench alias --waveform saw --oversampling 4
```

to investigate the loops, i sweep unison and voice count while holding the
other settings fixed. there are also zero-voice runs to measure the remaining
work:

```sh
build/bench scaling --blocks 5000 --baseline-blocks 50000
```

one of the first things i found was that the oscillator loop was computing
`sin`, `cos`, and frequency conversions for values that stayed the same during
a note. i moved those calculations to note-on and cached the results. now i'm
looking at the ladder filter and decimator costs.
