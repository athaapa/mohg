package mohg

import "core:math"

Ladder_Filter :: struct {
	sample_rate: f32,
	cutoff_hz:   f32,
	resonance:   f32,
	alpha:       f32,
	beta:        f32,
	stage:       [4]f32,
}

ladder_filter_set_sample_rate :: proc "contextless" (filter: ^Ladder_Filter, sample_rate: f32) {
	filter.sample_rate = math.max(sample_rate, 0)
	ladder_filter_calculate_coefficients(filter)
}

ladder_filter_calculate_coefficients :: proc "contextless" (filter: ^Ladder_Filter) {
	if filter.sample_rate <= 0 || filter.cutoff_hz <= 0 {
		filter.alpha = 1
		filter.beta = 0
		return
	}

	// Huovilainen polynomial for the one-pole coefficient g, valid for
	// omega_c = 2 pi fc / fs. Clamp so a high cutoff cannot push a pole
	// outside the unit circle.
	omega_c := 2.0 * math.PI * f64(filter.cutoff_hz) / f64(filter.sample_rate)
	wc2 := omega_c * omega_c
	alpha := 0.9892 * omega_c - 0.4342 * wc2 + 0.1381 * omega_c * wc2 - 0.0202 * wc2 * wc2

	filter.alpha = math.clamp(f32(alpha), 0.0, 0.999)
	filter.beta = 1.0 - filter.alpha
}

ladder_filter_set_parameters :: proc "contextless" (filter: ^Ladder_Filter, cutoff_hz: f32, resonance: f32) {
	max_cutoff := filter.sample_rate * 0.45
	if max_cutoff < 1.0 {
		max_cutoff = 1.0
	}

	filter.cutoff_hz = math.clamp(cutoff_hz, 1.0, max_cutoff)
	filter.resonance = math.clamp(resonance, 0.0, 1.0)
	ladder_filter_calculate_coefficients(filter)
}

ladder_filter_reset :: proc "contextless" (filter: ^Ladder_Filter) {
	filter.stage = [4]f32{}
}

ladder_filter_fast_tanh :: proc "contextless" (x: f32) -> f32 {
	x2 := x * x
	return x * (27.0 + x2) / (27.0 + 9.0 * x2)
}

ladder_filter_process_stage :: proc "contextless" (
	filter: ^Ladder_Filter,
	input: f32,
	stage: int,
) -> f32 {
	out := input * filter.alpha + filter.stage[stage] * filter.beta
	filter.stage[stage] = out
	return out
}

ladder_filter_process :: proc "contextless" (filter: ^Ladder_Filter, input: f32) -> f32 {
	if filter.sample_rate <= 0 {
		return input
	}

	k := filter.resonance * 4.0
	u := ladder_filter_fast_tanh(input - filter.stage[3] * k)

	s1 := ladder_filter_process_stage(filter, u, 0)
	s2 := ladder_filter_process_stage(filter, s1, 1)
	s3 := ladder_filter_process_stage(filter, s2, 2)
	s4 := ladder_filter_process_stage(filter, s3, 3)

	return s4
}
