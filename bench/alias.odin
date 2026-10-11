package bench

import mohg "../src"
import "core:fmt"
import "core:math"
import "core:os"

REFERENCE_FACTOR :: 8
SPECTRUM_FLOOR_DB :: -100.0

FFT_Value :: struct {
	re, im: f64,
}
Solver_Stats :: struct {
	max_iterations:   int,
	total_iterations: i64,
	failures:         int,
	worst_residual:   f32,
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
spectrum :: proc(samples: []f32) -> []f64 {
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
capture_filter :: proc(
	opts: Options,
	factor, tone_bin: int,
) -> (
	samples: []f32,
	stats: Solver_Stats,
	ok: bool,
) {
	rate := SAMPLE_RATE * factor
	n := opts.samples * factor
	frequency := f64(tone_bin) * SAMPLE_RATE / f64(opts.samples)
	filter := mohg.Ladder_Filter{}
	mohg.ladder_filter_set_sample_rate(&filter, f32(rate))
	mohg.ladder_filter_set_parameters(
		&filter,
		f32(opts.cutoff),
		f32(opts.resonance),
		f32(opts.drive),
	)
	samples = make([]f32, n)
	warmup := rate / 10
	for i in 0 ..< warmup + n {
		// Unit-peak sine. Drive is applied exactly once, inside ladder_filter_process.
		x := f32(math.sin(2 * math.PI * frequency * f64(i) / f64(rate)))
		y := mohg.ladder_filter_process(&filter, x)
		if math.is_nan(y) ||
		   math.is_inf(y) ||
		   math.is_nan(filter.last_residual) ||
		   math.is_inf(filter.last_residual) {
			return samples, stats, false
		}
		if i < warmup {continue}
		samples[i - warmup] = y
		stats.max_iterations = max(stats.max_iterations, filter.last_iterations)
		stats.total_iterations += i64(filter.last_iterations)
		stats.worst_residual = max(stats.worst_residual, filter.last_residual)
		if filter.last_residual >= mohg.TOLERANCE {stats.failures += 1}
	}
	return samples, stats, true
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

run_alias :: proc(opts: Options) {
	tone_bin := int(math.round(opts.frequency * f64(opts.samples) / SAMPLE_RATE))
	bin_hz := f64(SAMPLE_RATE) / f64(opts.samples)
	frequency := f64(tone_bin) * bin_hz
	fmt.printfln(
		"Alias experiment: %.3f Hz sine (requested %.3f Hz), %v Hz sample rate",
		frequency,
		opts.frequency,
		SAMPLE_RATE,
	)
	fmt.printfln(
		"Filter: %.1f Hz cutoff, %.3f resonance, %.3f drive; unit-peak input sine",
		opts.cutoff,
		opts.resonance,
		opts.drive,
	)
	fmt.printfln("%v samples, %.3f Hz/bin, Hann window; 0.1 s warmup", opts.samples, bin_hz)
	base, base_stats, base_ok := capture_filter(opts, 1, tone_bin)
	defer delete(base)
	ref, ref_stats, ref_ok := capture_filter(opts, REFERENCE_FACTOR, tone_bin)
	defer delete(ref)
	if !base_ok || !ref_ok {
		fmt.fprintln(os.stderr, "error: filter produced non-finite output or residual")
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
	print_spectrum("8x reference, shown only below 24 kHz", ref_amps, bin_hz, opts.width)
	fmt.println("\n   h    true Hz   lands Hz  kind       48k dBFS   ref dBFS")
	for h := 1; h <= 15; h += 2 {
		true_bin := h * tone_bin
		lands := fold_bin(true_bin, opts.samples)
		kind := true_bin <= opts.samples / 2 ? "harmonic" : "alias"
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
	fmt.printfln(
		"\n48k solver: max %v iterations, mean %.2f, worst residual %.3e, tolerance failures %v/%v",
		base_stats.max_iterations,
		f64(base_stats.total_iterations) / f64(len(base)),
		base_stats.worst_residual,
		base_stats.failures,
		len(base),
	)
	fmt.printfln(
		"8x solver:  max %v iterations, mean %.2f, worst residual %.3e, tolerance failures %v/%v",
		ref_stats.max_iterations,
		f64(ref_stats.total_iterations) / f64(len(ref)),
		ref_stats.worst_residual,
		ref_stats.failures,
		len(ref),
	)
}
