package mohg

import "core:math"
FIR_TAPS :: 257

Decimator :: struct {
	coeffs:  [FIR_TAPS]f64,
	history: [FIR_TAPS]f64,
	write:   int,
}

decimator_init :: proc(d: ^Decimator, oversampling_factor: u8, sample_rate: f64) {
	high_rate := sample_rate * f64(oversampling_factor)

	cutoff := sample_rate * 0.4375
	fc := cutoff / high_rate

	total: f64


	for k in 0 ..< FIR_TAPS {
		t := f64(k) - f64(FIR_TAPS - 1) / 2.0

		h: f64

		if t == 0 {
			h = 2.0 * fc
		} else {
			h = math.sin(2.0 * math.PI * fc * t) / (math.PI * t)
		}

		window := 0.54 - 0.46 * math.cos(math.TAU * f64(k) / f64(FIR_TAPS - 1))

		d.coeffs[k] = h * window
		total += d.coeffs[k]
	}

	for k in 0 ..< FIR_TAPS {
		d.coeffs[k] /= total
	}
}

decimator_push :: proc "contextless" (d: ^Decimator, sample: f64) {
	d.history[d.write] = sample
	d.write = (d.write + 1) % FIR_TAPS
}

decimator_output :: proc "contextless" (d: ^Decimator) -> f64 {
	result: f64

	for k in 0 ..< FIR_TAPS {
		idx := d.write - 1 - k

		if idx < 0 {
			idx += FIR_TAPS
		}

		result += d.coeffs[k] * d.history[idx]
	}

	return result
}
