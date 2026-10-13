package bench

import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"
import "core:strings"
import mohg "../src"

SAMPLE_RATE :: 48_000
CHANNEL_COUNT :: 2

MIN_VOICES :: 1
MAX_VOICES :: len(mohg.Voices{}.voices)
MIN_UNISON :: 1
MAX_UNISON :: len(mohg.Voice{}.oscillators)
MIN_FRAMES :: 1
MAX_FRAMES :: 4096
MIN_BLOCKS :: 1
MAX_BLOCKS :: 1000000
MIN_WARMUP :: 0
MAX_WARMUP :: 1000000
MIN_SAMPLES :: 1024
MAX_SAMPLES :: 65536
MIN_WIDTH :: 40
MAX_WIDTH :: 160
NYQUIST_HZ :: f64(SAMPLE_RATE) / 2
MIN_CUTOFF :: f64(mohg.LADDER_MIN_CUTOFF)
MAX_CUTOFF :: min(f64(mohg.LADDER_MAX_CUTOFF), 0.45 * SAMPLE_RATE)
MIN_RESONANCE :: f64(mohg.LADDER_MIN_RESONANCE)
MAX_RESONANCE :: f64(mohg.LADDER_MAX_RESONANCE)
MIN_DRIVE :: f64(mohg.LADDER_MIN_DRIVE)
MAX_DRIVE :: f64(mohg.LADDER_MAX_DRIVE)

Options :: struct {
	command: string,
	voices: int,
	sweep: bool,
	unison, frames, blocks, warmup: int,
	cutoff, resonance, drive, frequency: f64,
	samples, width: int,
	waveform: mohg.Waveform,
	oversampling: int,
}

default_options :: proc(command: string) -> Options {
	opts := Options{
		command = command, voices = min(32, MAX_VOICES), unison = min(16, MAX_UNISON),
		frames = 64, blocks = 1000, warmup = 100,
		cutoff = math.clamp(15000.0, MIN_CUTOFF, MAX_CUTOFF),
		resonance = math.clamp(0.9, MIN_RESONANCE, MAX_RESONANCE),
		drive = math.clamp(1.0, MIN_DRIVE, MAX_DRIVE),
		frequency = 5000, samples = 16384, width = 80,
		waveform = .SINE, oversampling = 1,
	}
	if command == "alias" {
		opts.cutoff = math.clamp(20000.0, MIN_CUTOFF, MAX_CUTOFF)
		opts.resonance = MIN_RESONANCE
		opts.drive = math.clamp(4.0, MIN_DRIVE, MAX_DRIVE)
	}
	return opts
}

range_error :: proc(name: string, lower, upper: $T, suffix := "") -> string {
	return fmt.tprintf("%s must be %v..%v%s", name, lower, upper, suffix)
}

usage :: proc() {
	render := default_options("render")
	alias := default_options("alias")
	fmt.printfln(`Usage: build/bench <render|alias> [options]

render  Offline synth render timing (defaults to %v voices, %v unison)
  --voices N       %v..%v voices (default %v)
  --sweep          Run 16/32/64/128 voices instead; cannot combine with --voices
  --unison N       %v..%v oscillators per voice (default %v)
  --oversampling N  1, 2, 4, 8, 16 (default 1)
  --frames N       %v..%v frames per block (default %v)
  --blocks N       %v..%v measured blocks (default %v)
  --warmup N       %v..%v warmup blocks (default %v)
  --cutoff HZ      Filter cutoff (default %v)
  --resonance R    %v..%v (default %v)
  --drive D        %v..%v (default %v)

alias   Full synth render; ASCII frequency spectra and candidate folds
  --waveform W    sine, saw, square, triangle (default sine)
  --oversampling N  1, 2, 4, 8, 16 (default 1)
  --cutoff HZ      Filter cutoff (default %v)
  --resonance R    %v..%v (default %v)
  --drive D        %v..%v, applied by the filter (default %v)
  --frequency HZ  Oscillator frequency (default %v; snapped to an FFT bin)
  --samples N     Power of two, %v..%v (default %v)
  --width N       Spectrum columns, %v..%v (default %v)

Cutoff range: %v..%v Hz at the fixed %v Hz sample rate.
Use --help with either command. Options accept --name value or --name=value.
Examples:
  build/bench render
  build/bench alias
  build/bench render --voices 32 --unison 8
  build/bench alias --cutoff %v --resonance %v --drive %v`,
		render.voices, render.unison,
		MIN_VOICES, MAX_VOICES, render.voices,
		MIN_UNISON, MAX_UNISON, render.unison,
		MIN_FRAMES, MAX_FRAMES, render.frames,
		MIN_BLOCKS, MAX_BLOCKS, render.blocks,
		MIN_WARMUP, MAX_WARMUP, render.warmup,
		render.cutoff, MIN_RESONANCE, MAX_RESONANCE, render.resonance,
		MIN_DRIVE, MAX_DRIVE, render.drive,
		alias.cutoff, MIN_RESONANCE, MAX_RESONANCE, alias.resonance,
		MIN_DRIVE, MAX_DRIVE, alias.drive, alias.frequency,
		MIN_SAMPLES, MAX_SAMPLES, alias.samples, MIN_WIDTH, MAX_WIDTH, alias.width,
		MIN_CUTOFF, MAX_CUTOFF, SAMPLE_RATE, alias.cutoff, alias.resonance, alias.drive,
	)
}

parse_options :: proc(args: []string) -> (opts: Options, err: string) {
	if len(args) == 0 || (args[0] != "render" && args[0] != "alias") {
		return {}, "expected subcommand 'render' or 'alias'"
	}
	opts = default_options(args[0])
	seen := make(map[string]bool)
	defer delete(seen)
	for i := 1; i < len(args); i += 1 {
		name, value := args[i], ""
		if name == "--sweep" {
			if opts.command != "render" { return opts, "--sweep is only available for render" }
			if seen[name] { return opts, "duplicate option --sweep" }
			seen[name] = true
			opts.sweep = true
			continue
		}
		if pos := strings.index_byte(name, '='); pos >= 0 {
			value, name = name[pos + 1:], name[:pos]
		} else {
			if i + 1 >= len(args) { return opts, fmt.tprintf("missing value for %s", name) }
			i += 1
			value = args[i]
		}
		if seen[name] { return opts, fmt.tprintf("duplicate option %s", name) }
		seen[name] = true
		switch name {
		case "--waveform":
			if opts.command != "alias" { return opts, "--waveform is only available for alias" }
			switch value {
			case "sine": opts.waveform = .SINE
			case "saw": opts.waveform = .SAW
			case "square": opts.waveform = .SQUARE
			case "triangle": opts.waveform = .TRIANGLE
			case: return opts, "--waveform must be sine, saw, square, or triangle"
			}
		case "--oversampling":
			n, ok := strconv.parse_int(value, 10)
			if !ok || (n != 1 && n != 2 && n != 4 && n != 8 && n != 16) {
				return opts, "--oversampling must be 1, 2, 4, 8, or 16"
			}
			opts.oversampling = n
		case "--cutoff", "--resonance", "--drive", "--frequency":
			if name == "--frequency" && opts.command != "alias" {
				return opts, "--frequency is only available for alias"
			}
			n, ok := strconv.parse_f64(value)
			if !ok || math.is_nan(n) || math.is_inf(n) {
				return opts, fmt.tprintf("%s requires a finite number", name)
			}
			switch name {
			case "--cutoff": opts.cutoff = n
			case "--resonance": opts.resonance = n
			case "--drive": opts.drive = n
			case "--frequency": opts.frequency = n
			}
		case "--voices", "--unison", "--frames", "--blocks", "--warmup", "--samples", "--width":
			alias_option := name == "--samples" || name == "--width"
			if alias_option != (opts.command == "alias") {
				return opts, fmt.tprintf("%s is not available for %s", name, opts.command)
			}
			n, ok := strconv.parse_int(value, 10)
			if !ok { return opts, fmt.tprintf("%s requires an integer", name) }
			switch name {
			case "--voices":
				if n < MIN_VOICES || n > MAX_VOICES { return opts, range_error(name, MIN_VOICES, MAX_VOICES) }
				opts.voices = n
			case "--unison":
				if n < MIN_UNISON || n > MAX_UNISON { return opts, range_error(name, MIN_UNISON, MAX_UNISON) }
				opts.unison = n
			case "--frames":
				if n < MIN_FRAMES || n > MAX_FRAMES { return opts, range_error(name, MIN_FRAMES, MAX_FRAMES) }
				opts.frames = n
			case "--blocks":
				if n < MIN_BLOCKS || n > MAX_BLOCKS { return opts, range_error(name, MIN_BLOCKS, MAX_BLOCKS) }
				opts.blocks = n
			case "--warmup":
				if n < MIN_WARMUP || n > MAX_WARMUP { return opts, range_error(name, MIN_WARMUP, MAX_WARMUP) }
				opts.warmup = n
			case "--samples":
				if n < MIN_SAMPLES || n > MAX_SAMPLES || (n & (n - 1)) != 0 {
					return opts, fmt.tprintf("%s must be a power of two in %v..%v", name, MIN_SAMPLES, MAX_SAMPLES)
				}
				opts.samples = n
			case "--width":
				if n < MIN_WIDTH || n > MAX_WIDTH { return opts, range_error(name, MIN_WIDTH, MAX_WIDTH) }
				opts.width = n
			}
		case: return opts, fmt.tprintf("unknown option %s", name)
		}
	}
	if opts.sweep && seen["--voices"] { return opts, "--sweep cannot be combined with --voices" }
	if opts.cutoff < MIN_CUTOFF || opts.cutoff > MAX_CUTOFF {
		return opts, range_error("--cutoff", MIN_CUTOFF, MAX_CUTOFF, " Hz")
	}
	if opts.resonance < MIN_RESONANCE || opts.resonance > MAX_RESONANCE {
		return opts, range_error("--resonance", MIN_RESONANCE, MAX_RESONANCE)
	}
	if opts.drive < MIN_DRIVE || opts.drive > MAX_DRIVE {
		return opts, range_error("--drive", MIN_DRIVE, MAX_DRIVE, " (the filter's supported range)")
	}
	if opts.frequency <= 0 || opts.frequency >= NYQUIST_HZ {
		return opts, fmt.tprintf("--frequency must be above zero and below %v Hz", NYQUIST_HZ)
	}
	if opts.command == "alias" {
		bin := int(math.round(opts.frequency * f64(opts.samples) / SAMPLE_RATE))
		if bin < 1 || bin >= opts.samples / 2 {
			return opts, "--frequency rounds to DC or Nyquist; use a different frequency or more samples"
		}
	}
	return
}

main :: proc() {
	args := os.args[1:]
	if len(args) == 0 { usage(); return }
	for arg in args {
		if arg == "--help" || arg == "-h" { usage(); return }
	}
	opts, err := parse_options(args)
	if err != "" {
		fmt.fprintln(os.stderr, "error:", err)
		os.exit(1)
	}
	switch opts.command {
	case "render": run_render(opts)
	case "alias": run_alias(opts)
	}
}
