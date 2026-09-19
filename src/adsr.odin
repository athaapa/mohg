package mohg

import "core:math"

ADSR_State :: enum {
	IDLE,
	ATTACK,
	DECAY,
	SUSTAIN,
	RELEASE,
}

on_idle :: proc "contextless" (synth: ^Synth) -> ADSR_State {
	if synth.gate {
		return ADSR_State.ATTACK
	}

	return ADSR_State.IDLE
}

on_attack :: proc "contextless" (synth: ^Synth) -> ADSR_State {
	if !synth.gate {
		return ADSR_State.RELEASE
	}

	sample_rate := synth.sample_rate
	adsr_config := synth.adsr_config
	attack_seconds := adsr_config.attack_seconds

	attack_step := f64(1.0) / (attack_seconds * sample_rate)

	synth.current_amplitude = math.min(1.0, synth.current_amplitude + attack_step)

	if synth.current_amplitude == 1.0 {
		return ADSR_State.DECAY
	}

	return ADSR_State.ATTACK
}

on_decay :: proc "contextless" (synth: ^Synth) -> ADSR_State {
	if !synth.gate {
		return ADSR_State.RELEASE
	}

	sample_rate := synth.sample_rate
	adsr_config := synth.adsr_config
	sustain_level := adsr_config.sustain_level
	decay_seconds := adsr_config.decay_seconds

	decay_step := (1.0 - sustain_level) / (decay_seconds * synth.sample_rate)

	synth.current_amplitude = math.max(sustain_level, synth.current_amplitude - decay_step)


	if (synth.current_amplitude == sustain_level) {
		return ADSR_State.SUSTAIN
	}


	return ADSR_State.DECAY
}

on_sustain :: proc "contextless" (synth: ^Synth) -> ADSR_State {
	if !synth.gate {
		return ADSR_State.RELEASE
	}

	return ADSR_State.SUSTAIN
}

on_release :: proc "contextless" (synth: ^Synth) -> ADSR_State {
	if synth.gate {
		return ADSR_State.ATTACK
	}

	sample_rate := synth.sample_rate
	adsr_config := synth.adsr_config
	release_seconds := adsr_config.release_seconds
	release_samples := release_seconds * synth.sample_rate

	release_multiplier := math.exp(-6.91 / release_samples)
	release_target := -0.001

	synth.current_amplitude =
		release_target + (synth.current_amplitude - release_target) * release_multiplier

	if synth.current_amplitude <= 0.0 {
		synth.current_amplitude = 0.0
		return ADSR_State.IDLE
	}

	return ADSR_State.RELEASE
}
