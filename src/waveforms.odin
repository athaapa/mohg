package mohg

import "core:math"

generate_sine_wave :: proc "contextless" (phase: f64) -> f64 {
	return math.sin(2 * math.PI * phase)
}

generate_square_wave :: proc "contextless" (phase: f64) -> f64 {
	if phase < 0.5 {
		return 1
	}
	return -1
}

generate_triangle_wave :: proc "contextless" (phase: f64) -> f64 {
	return 1.0 - 4.0 * math.abs(phase - 0.5)
}

generate_saw_wave :: proc "contextless" (phase: f64) -> f64 {
	return 2.0 * phase - 1.0
}
