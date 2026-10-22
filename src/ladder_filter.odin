package mohg

import "core:math"

LADDER_MAX_CUTOFF :: 24_000
LADDER_MIN_CUTOFF :: 600

LADDER_MIN_RESONANCE :: 0
LADDER_MAX_RESONANCE :: 1.0

LADDER_MAX_DRIVE :: 8
LADDER_MIN_DRIVE :: 0.1

TOLERANCE: f64 : 1e-6
MAX_ITERATIONS :: 8


Ladder_Filter :: struct {
	sample_rate:     f64,
	cutoff_hz:       f64,
	resonance:       f64,
	stage:           [4]f64,
	G:               f64,
	last_iterations: int,
	last_residual:   f64,
	drive:           f64,
	last_u:          f64,
}


ladder_filter_set_sample_rate :: proc "contextless" (filter: ^Ladder_Filter, sample_rate: f64) {
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
	cutoff_hz: f64,
	resonance: f64,
	drive: f64,
) {

	filter.cutoff_hz = math.clamp(cutoff_hz, LADDER_MIN_CUTOFF, LADDER_MAX_CUTOFF)
	filter.resonance = math.clamp(resonance, LADDER_MIN_RESONANCE, LADDER_MAX_RESONANCE)
	filter.drive = math.clamp(drive, LADDER_MIN_DRIVE, LADDER_MAX_DRIVE)
	ladder_filter_calculate_coefficients(filter)
}

ladder_filter_reset :: proc "contextless" (filter: ^Ladder_Filter) {
	filter.stage = [4]f64{}
	filter.last_u = 0
}

ladder_filter_process_stage :: proc "contextless" (
	filter: ^Ladder_Filter,
	input: f64,
	stage: int,
) -> f64 {
	G := filter.G

	v := (input - filter.stage[stage]) * G
	out := v + filter.stage[stage]
	filter.stage[stage] = out + v
	filter.G = G

	return out
}

ladder_calculate_state_contribution :: proc "contextless" (filter: ^Ladder_Filter) -> f64 {
	G := filter.G
	omG := 1.0 - G

	G2 := G * G
	G3 := G2 * G

	return(
		omG *
		(G3 * filter.stage[0] + G2 * filter.stage[1] + G * filter.stage[2] + filter.stage[3]) \
	)
}

ladder_forward :: proc "contextless" (filter: ^Ladder_Filter, u: f64) -> (y4: f64, dy4_du: f64) {
	G := filter.G
	omG := 1.0 - G
	x := u
	d := 1.0
	for i in 0 ..< 4 {
		t := fast_tanh(x)
		d *= G * (1.0 - t * t)
		x = G * t + omG * filter.stage[i]
	}
	return x, d
}

ladder_filter_process :: proc "contextless" (filter: ^Ladder_Filter, input: f64) -> f64 {
	if filter.sample_rate <= 0 {
		return input
	}
	input := input * filter.drive
	k := filter.resonance * 4.0
	u := filter.last_u
	for i in 0 ..< MAX_ITERATIONS {
		y4, dy4 := ladder_forward(filter, u)
		F_u := u + k * y4 - input
		filter.last_iterations = i + 1
		filter.last_residual = math.abs(F_u)
		if math.abs(F_u) < TOLERANCE {
			break
		}
		u -= F_u / (1.0 + k * dy4)
	}
	filter.last_u = u
	x := u
	for i in 0 ..< 4 {
		x = ladder_filter_process_stage(filter, fast_tanh(x), i)
	}
	return x / filter.drive
}
