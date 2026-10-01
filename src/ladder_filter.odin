package mohg

import "core:math"

LADDER_MIN_CUTOFF :: 20
LADDER_MAX_CUTOFF :: 20_000
TOLERANCE: f32 : 1e-6
MAX_ITERATIONS :: 8


Ladder_Filter :: struct {
	sample_rate: f32,
	cutoff_hz:   f32,
	resonance:   f32,
	stage:       [4]f32,
	G:           f32,
}

ladder_filter_set_sample_rate :: proc "contextless" (filter: ^Ladder_Filter, sample_rate: f32) {
	filter.sample_rate = math.max(sample_rate, 0)
	ladder_filter_calculate_coefficients(filter)
}

ladder_filter_calculate_coefficients :: proc "contextless" (filter: ^Ladder_Filter) {
	g := math.tan(math.PI * filter.cutoff_hz / filter.sample_rate)
	G := g / (1 + g)
	filter.G = G
}

ladder_filter_set_parameters :: proc "contextless" (
	filter: ^Ladder_Filter,
	cutoff_hz: f32,
	resonance: f32,
) {
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

ladder_filter_process_stage :: proc "contextless" (
	filter: ^Ladder_Filter,
	input: f32,
	stage: int,
) -> f32 {
	G := filter.G

	v := (input - filter.stage[stage]) * G
	out := v + filter.stage[stage]
	filter.stage[stage] = out + v
	filter.G = G

	return out
}

ladder_calculate_state_contribution :: proc "contextless" (filter: ^Ladder_Filter) -> f32 {
	G := filter.G
	omG := 1.0 - G

	G2 := G * G
	G3 := G2 * G

	return(
		omG *
		(G3 * filter.stage[0] + G2 * filter.stage[1] + G * filter.stage[2] + filter.stage[3]) \
	)
}

ladder_filter_process :: proc "contextless" (filter: ^Ladder_Filter, input: f32) -> f32 {
	if filter.sample_rate <= 0 {
		return input
	}

	k := filter.resonance * 4.0

	S := ladder_calculate_state_contribution(filter)
	g4 := filter.G * filter.G * filter.G * filter.G
	A := g4

	u := (input - k * S) / (1.0 + k * g4)

	for _ in 0 ..< MAX_ITERATIONS {
		u_tanh := math.tanh(u)
		u = u - (u + k * (A * u_tanh + S) - input) / (1 + k * A * (1 - u_tanh * u_tanh))
		u_tanh = math.tanh(u)
		F_u := u + k * (A * u_tanh + S) - input
		if (math.abs(F_u) < TOLERANCE) {
			break
		}
	}

	s1 := ladder_filter_process_stage(filter, math.tanh(u), 0)
	s2 := ladder_filter_process_stage(filter, s1, 1)
	s3 := ladder_filter_process_stage(filter, s2, 2)
	s4 := ladder_filter_process_stage(filter, s3, 3)

	return s4
}
