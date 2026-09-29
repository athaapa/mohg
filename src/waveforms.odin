package mohg

import "core:math"

generate_sine_wave :: proc "contextless" (phase: f64) -> f64 {
	return math.sin(2 * math.PI * phase)
}

generate_square_wave :: proc "contextless" (phase: f64, step: f64) -> f64 {
	wave := f64(-1)
	if phase < 0.5 {
		wave = 1
	}

	wave += poly_blep(phase, step)
	wave -= poly_blep(math.mod_f64(phase + 0.5, 1.0), step)

	return wave
}

generate_triangle_wave :: proc "contextless" (phase: f64, step: f64) -> f64 {
	wave := 1.0 - 4.0 * math.abs(phase - 0.5)

	wave += poly_blamp(phase, step)
	wave += poly_blamp(1.0 - phase, step)

	shifted_phase := phase + 0.5
	if (shifted_phase >= 1.0) {shifted_phase -= 1.0}

	wave -= poly_blamp(shifted_phase, step)
	wave -= poly_blamp(1.0 - shifted_phase, step)

	return wave

}

generate_saw_wave :: proc "contextless" (phase: f64, step: f64) -> f64 {
	wave := 2.0 * phase - 1.0

	corrected := wave - poly_blep(phase, step)

	return corrected
}
