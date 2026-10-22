package bench

import mohg "../src"
import "core:fmt"
import "core:math"
import "core:os"

REFERENCE_FACTOR :: 8
SPECTRUM_FLOOR_DB :: -100.0
ALIAS_MAX_HARMONIC :: 63

FFT_Value :: struct {
	re, im: f64,
}

// Radix-2 forward FFT. No allocations or normalization inside the transform.
fft :: proc(data: []FFT_Value) {
	n := len(data)
	assert(n > 0 && (n & (n - 1)) == 0)
	j := 0
	for i in 1 ..< n {
		bit := n >> 1
		for (j & bit) != 0 {j ~= bit; bit >>= 1}
		j ~= bit
		if i < j {data[i], data[j] = data[j], data[i]}
	}
	for size := 2; size <= n; size *= 2 {
		angle := -2 * math.PI / f64(size)
		step := FFT_Value{math.cos(angle), math.sin(angle)}
		for start := 0; start < n; start += size {
			w := FFT_Value{1, 0}
			for offset in 0 ..< size / 2 {
				left := data[start + offset]
				right := data[start + offset + size / 2]
				t := FFT_Value {
					right.re * w.re - right.im * w.im,
					right.re * w.im + right.im * w.re,
				}
				data[start + offset] = FFT_Value{left.re + t.re, left.im + t.im}
				data[start + offset + size / 2] = FFT_Value{left.re - t.re, left.im - t.im}
				w = FFT_Value{w.re * step.re - w.im * step.im, w.re * step.im + w.im * step.re}
			}
		}
	}
}

// One-sided peak amplitudes with periodic Hann window/coherent-gain correction.
// An on-bin sine of peak amplitude 1 reads 0 dBFS. DC/Nyquist are not doubled.
spectrum :: proc(samples: []f64) -> []f64 {
	n := len(samples)
	data := make([]FFT_Value, n)
	defer delete(data)
	window_sum: f64
	for sample, i in samples {
		window := 0.5 - 0.5 * math.cos(2 * math.PI * f64(i) / f64(n))
		window_sum += window
		data[i].re = f64(sample) * window
	}
	fft(data)
	amps := make([]f64, n / 2 + 1)
	for value, i in data[:n / 2 + 1] {
		scale := (i == 0 || i == n / 2) ? 1.0 : 2.0
		amps[i] = scale * math.sqrt(value.re * value.re + value.im * value.im) / window_sum
	}
	return amps
}

amplitude_db :: proc(amplitude: f64) -> f64 {
	return 20 * math.log10(math.max(amplitude, 1e-12))
}

// Both captures have the same duration and frequency spacing. Keeping the
// same integer tone bin at 8x gives exactly the same input frequency in Hz.
capture_synth :: proc(opts: Options, factor, tone_bin: int) -> (samples: []f64, ok: bool) {
	rate := SAMPLE_RATE * factor
	n := opts.samples * factor
	frequency := f64(tone_bin) * SAMPLE_RATE / f64(opts.samples)
	voices := mohg.Voices{}
	synth := mohg.Synth {
		sample_rate = f64(rate),
		voices = &voices,
		max_voices = 1,
		unison_count = 1,
		waveform = opts.waveform,
		oversampling_factor = u8(opts.oversampling),
		adsr_config = mohg.ADSR_Config {
			attack_seconds = 0.025,
			decay_seconds = 0.025,
			sustain_level = 1,
			release_seconds = 0.1,
		},
		rng = mohg.RNG{state = 1},
	}
	mohg.ladder_filter_set_sample_rate(&synth.ladder_filter, f64(rate * opts.oversampling))
	mohg.ladder_filter_set_parameters(
		&synth.ladder_filter,
		opts.cutoff,
		opts.resonance,
		opts.drive,
	)
	mohg.decimator_init(&synth.left_decimator, synth.oversampling_factor, synth.sample_rate)
	mohg.decimator_init(&synth.right_decimator, synth.oversampling_factor, synth.sample_rate)
	midi := mohg.Spsc_Queue(mohg.Midi_Event, mohg.MIDI_QUEUE_CAPACITY){}
	parameters := mohg.Spsc_Queue(mohg.Parameter_Event, mohg.PARAMETER_QUEUE_CAPACITY){}
	assert(mohg.spsc_try_push(&midi, mohg.Midi_Note_On{note = 69, velocity = 100}))
	mohg.synth_process_midi(&synth, &midi, &parameters)
	// Exact FFT-bin tuning avoids confusing leakage with aliasing. All signal
	// generation after this setup goes through the production renderer.
	voice := &voices.voices[0]
	voice.frequency = frequency
	oversampled_rate := synth.sample_rate * f64(synth.oversampling_factor)
	for osc_idx in 0 ..< synth.unison_count {
		osc := &voice.oscillators[osc_idx]
		cents := voice.tune_cents + osc.detune + osc.static_cents
		mohg.oscillator_set_frequency(
			osc,
			frequency * mohg.cents_to_freq_multiplier(cents),
			oversampled_rate,
		)
	}
	samples = make([]f64, n)
	warmup := rate / 10
	buffer: [64 * CHANNEL_COUNT]f32
	position := 0
	for position < warmup + n {
		frames := min(64, warmup + n - position)
		mohg.synth_render(&synth, raw_data(buffer[:]), frames, CHANNEL_COUNT)
		for frame in 0 ..< frames {
			left := f64(buffer[frame * CHANNEL_COUNT])
			right := f64(buffer[frame * CHANNEL_COUNT + 1])
			if math.is_nan(left) || math.is_inf(left) || math.is_nan(right) || math.is_inf(right) {
				return samples, false
			}
			index := position + frame - warmup
			if index >= 0 {samples[index] = left}
		}
		position += frames
	}
	return samples, true
}

// Linear Hz x-axis. Each column preserves the strongest FFT bin in its range;
// it is a peak spectrum, not an integrated power-per-band histogram.
print_spectrum :: proc(title: string, amps: []f64, bin_hz: f64, width: int) {
	fmt.printfln("\n%s", title)
	columns := make([]f64, width)
	defer delete(columns)
	max_bin := min(len(amps) - 1, int((SAMPLE_RATE / 2) / bin_hz))
	for i in 0 ..= max_bin {
		column := min(width - 1, i * width / max_bin)
		columns[column] = max(columns[column], amps[i])
	}
	row := make([]u8, width)
	defer delete(row)
	fmt.println("  dBFS |")
	for level := 0; level >= int(SPECTRUM_FLOOR_DB); level -= 10 {
		for amp, i in columns {
			db := amplitude_db(amp)
			row[i] = db > SPECTRUM_FLOOR_DB && db >= f64(level) ? '#' : ' '
		}
		fmt.printfln("%6s |%s", fmt.tprint(level), string(row))
	}
	for &cell in row {cell = '-'}
	fmt.printfln("       +%s", string(row))
	for &cell in row {cell = ' '}
	for tick in 0 ..= 6 {
		label := fmt.tprintf("%vk", tick * 4)
		pos := tick * (width - 1) / 6
		pos = min(pos, width - len(label))
		copy(row[pos:], transmute([]u8)label)
	}
	fmt.printfln("        %s Hz", string(row))
}

fold_bin :: proc(bin, count: int) -> int {
	wrapped := bin % count
	return wrapped > count / 2 ? count - wrapped : wrapped
}

Alias_Energy :: struct {
	total_db:    f64,
	largest_db:  f64,
	largest_bin: int,
	components:  int,
}

// Sums power only at the bins where harmonics above the output Nyquist land,
// relative to the fundamental. Summing every non-harmonic bin would mostly
// measure the voice noise, which the decimator also attenuates with oversampling.
// Folds that land on DC or an in-band harmonic are skipped because they can't
// be separated from real content.
alias_energy :: proc(amps: []f64, tone_bin, samples, oversampling: int) -> Alias_Energy {
	counted := make([]bool, samples / 2 + 1)
	defer delete(counted)
	result := Alias_Energy{largest_db = SPECTRUM_FLOOR_DB}
	power: f64
	fundamental := amps[tone_bin] * amps[tone_bin]
	for h in 2 ..= ALIAS_MAX_HARMONIC {
		true_bin := h * tone_bin
		if true_bin <= samples / 2 {continue}
		lands := fold_bin(fold_bin(true_bin, samples * oversampling), samples)
		if lands == 0 || lands % tone_bin == 0 || counted[lands] {continue}
		counted[lands] = true
		power += amps[lands] * amps[lands]
		result.components += 1
		db := amplitude_db(amps[lands] / amps[tone_bin])
		if db > result.largest_db {
			result.largest_db = db
			result.largest_bin = lands
		}
	}
	result.total_db = 10 * math.log10(math.max(power / fundamental, 1e-24))
	return result
}

run_alias :: proc(opts: Options) {
	tone_bin := int(math.round(opts.frequency * f64(opts.samples) / SAMPLE_RATE))
	bin_hz := f64(SAMPLE_RATE) / f64(opts.samples)
	frequency := f64(tone_bin) * bin_hz
	fmt.printfln(
		"Synth alias experiment: %.3f Hz %v (requested %.3f Hz), %v Hz output rate",
		frequency,
		opts.waveform,
		opts.frequency,
		SAMPLE_RATE,
	)
	fmt.printfln(
		"Filter: %.1f Hz cutoff, %.3f resonance, %.3f drive",
		opts.cutoff,
		opts.resonance,
		opts.drive,
	)
	fmt.printfln(
		"One sustained voice, one oscillator, %vx internal oversampling; left-channel output",
		opts.oversampling,
	)
	fmt.printfln("%v samples, %.3f Hz/bin, Hann window; 0.1 s warmup", opts.samples, bin_hz)
	base, base_ok := capture_synth(opts, 1, tone_bin)
	defer delete(base)
	ref, ref_ok := capture_synth(opts, REFERENCE_FACTOR, tone_bin)
	defer delete(ref)
	if !base_ok || !ref_ok {
		fmt.fprintln(os.stderr, "error: synth produced non-finite output")
		os.exit(1)
	}
	base_amps := spectrum(base)
	defer delete(base_amps)
	ref_amps := spectrum(ref)
	defer delete(ref_amps)
	print_spectrum(
		"48 kHz output (peak amplitude per frequency column)",
		base_amps,
		bin_hz,
		opts.width,
	)
	print_spectrum(
		"384 kHz synth reference, shown only below 24 kHz",
		ref_amps,
		bin_hz,
		opts.width,
	)
	fmt.println("\nFold locations below are candidates, not isolated alias measurements.")
	fmt.println(
		"stopband = above output Nyquist after folding at the internal rate; FIR attenuation applies.",
	)
	fmt.println("\n   h    true Hz   lands Hz  kind       48k dBFS   ref dBFS")
	harmonic_step := 2
	if opts.waveform == .SAW {harmonic_step = 1}
	for h := 1; h <= 15; h += harmonic_step {
		true_bin := h * tone_bin
		internal_lands := fold_bin(true_bin, opts.samples * opts.oversampling)
		lands := fold_bin(internal_lands, opts.samples)
		kind := "harmonic"
		if true_bin > opts.samples / 2 {kind = "alias"}
		if internal_lands > opts.samples / 2 {kind = "stopband"}
		if kind == "alias" && lands % tone_bin == 0 {kind = "overlap"}
		fmt.printfln(
			"%4s %10s %10s  %-8s %10s %10s",
			fmt.tprint(h),
			fmt.tprintf("%.1f", f64(true_bin) * bin_hz),
			fmt.tprintf("%.1f", f64(lands) * bin_hz),
			kind,
			fmt.tprintf("%.1f", amplitude_db(base_amps[lands])),
			fmt.tprintf("%.1f", amplitude_db(ref_amps[lands])),
		)
	}

	base_alias := alias_energy(base_amps, tone_bin, opts.samples, opts.oversampling)
	ref_alias := alias_energy(ref_amps, tone_bin, opts.samples, opts.oversampling)
	fmt.printfln(
		"\nFolded harmonics 2..%v, power at their 48 kHz landing bins relative to the fundamental:",
		ALIAS_MAX_HARMONIC,
	)
	fmt.printfln("  fundamental:      %.1f dBFS", amplitude_db(base_amps[tone_bin]))
	fmt.printfln(
		"  48 kHz output:    %.1f dB total over %v bins, largest %.1f dB at %.1f Hz",
		base_alias.total_db,
		base_alias.components,
		base_alias.largest_db,
		f64(base_alias.largest_bin) * bin_hz,
	)
	fmt.printfln(
		"  same bins in ref: %.1f dB total, largest %.1f dB",
		ref_alias.total_db,
		ref_alias.largest_db,
	)
}
