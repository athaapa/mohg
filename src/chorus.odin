package mohg

import "core:math"

CHORUS_BUFFER_SIZE :: 2048 // power of two, enough for ~10 ms at 192 kHz
CHORUS_BUFFER_MASK :: CHORUS_BUFFER_SIZE - 1

Chorus_Mode :: enum {
	OFF,
	I,
	II,
	I_II,
}

Chorus :: struct {
	sample_rate: f64,
	mode:        Chorus_Mode,
	buffer:      [CHORUS_BUFFER_SIZE]f64,
	write_index: int,
	lfo_phase:   f64,
	lfo_step:    f64,
	center_ms:   f64,
	depth_ms:    f64,
	mix:         f64,
	lp_coeff:    f64,
	pre_lp:      f64,
	post_lp_l:   f64,
	post_lp_r:   f64,
}

chorus_init :: proc "contextless" (chorus: ^Chorus, sample_rate: f64) {
	chorus^ = {}
	chorus.sample_rate = sample_rate
	chorus.mix = 1
	chorus.lp_coeff = 1.0 - math.exp(-math.TAU * 8000.0 / sample_rate)
	chorus_set_mode(chorus, .OFF)
}

chorus_set_mode :: proc "contextless" (chorus: ^Chorus, mode: Chorus_Mode) {
	chorus.mode = mode
	rate_hz, min_ms, max_ms: f64
	switch mode {
	case .OFF:
		return
	case .I:
		rate_hz, min_ms, max_ms = 0.513, 1.66, 5.35
	case .II:
		rate_hz, min_ms, max_ms = 0.863, 1.66, 5.35
	case .I_II:
		rate_hz, min_ms, max_ms = 9.75, 3.30, 3.70
	}
	chorus.lfo_step = rate_hz / chorus.sample_rate
	chorus.center_ms = 0.5 * (min_ms + max_ms)
	chorus.depth_ms = 0.5 * (max_ms - min_ms)
}

@(private = "file")
chorus_read :: proc "contextless" (chorus: ^Chorus, delay_ms: f64) -> f64 {
	delay_samples := delay_ms * chorus.sample_rate / 1000.0
	read_pos := f64(chorus.write_index) - delay_samples
	base := math.floor(read_pos)
	frac := read_pos - base
	i0 := int(base) & CHORUS_BUFFER_MASK
	i1 := (i0 + 1) & CHORUS_BUFFER_MASK
	return chorus.buffer[i0] + frac * (chorus.buffer[i1] - chorus.buffer[i0])
}

chorus_process :: proc "contextless" (sample: Stereo64, chorus: ^Chorus) -> Stereo64 {
	if chorus.mode == .OFF {
		return sample
	}

	left := sample[0]
	right := sample[1]

	a := chorus.lp_coeff

	input := 0.5 * (left + right)
	chorus.pre_lp += a * (input - chorus.pre_lp)
	chorus.buffer[chorus.write_index] = fast_tanh(chorus.pre_lp * 1.5) / 1.5

	lfo := 4.0 * math.abs(chorus.lfo_phase - 0.5) - 1.0
	chorus.lfo_phase += chorus.lfo_step
	if chorus.lfo_phase >= 1 {
		chorus.lfo_phase -= 1
	}

	wet_l := chorus_read(chorus, chorus.center_ms + chorus.depth_ms * lfo)
	wet_r := chorus_read(chorus, chorus.center_ms - chorus.depth_ms * lfo)

	chorus.post_lp_l += a * (wet_l - chorus.post_lp_l)
	chorus.post_lp_r += a * (wet_r - chorus.post_lp_r)

	chorus.write_index = (chorus.write_index + 1) & CHORUS_BUFFER_MASK

	return Stereo64 {
		0.7 * (left + chorus.mix * chorus.post_lp_l),
		0.7 * (right + chorus.mix * chorus.post_lp_r),
	}
}
