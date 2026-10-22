package mohg

import "core:math"

ADSR_State :: enum {
	IDLE,
	ATTACK,
	DECAY,
	SUSTAIN,
	RELEASE,
}

on_idle :: proc "contextless" (voice: ^Voice) -> ADSR_State {
	if voice.gate {
		return ADSR_State.ATTACK
	}

	return ADSR_State.IDLE
}

on_attack :: proc "contextless" (
	voice: ^Voice,
	sample_rate: f64,
	attack_seconds: f64,
) -> ADSR_State {
	if !voice.gate {
		return ADSR_State.RELEASE
	}

	attack_step := f64(1.0) / (attack_seconds * sample_rate)

	voice.current_amplitude = math.min(1.0, voice.current_amplitude + attack_step)

	if voice.current_amplitude == 1.0 {
		return ADSR_State.DECAY
	}

	return ADSR_State.ATTACK
}

on_decay :: proc "contextless" (
	voice: ^Voice,
	sample_rate: f64,
	sustain_level: f64,
	decay_seconds: f64,
) -> ADSR_State {
	if !voice.gate {
		return ADSR_State.RELEASE
	}


	decay_step := (1.0 - sustain_level) / (decay_seconds * sample_rate)

	voice.current_amplitude = math.max(sustain_level, voice.current_amplitude - decay_step)


	if (voice.current_amplitude == sustain_level) {
		return ADSR_State.SUSTAIN
	}


	return ADSR_State.DECAY
}

on_sustain :: proc "contextless" (voice: ^Voice) -> ADSR_State {
	if !voice.gate {
		return ADSR_State.RELEASE
	}

	return ADSR_State.SUSTAIN
}

on_release :: proc "contextless" (
	voice: ^Voice,
	sample_rate: f64,
	release_seconds: f64,
) -> ADSR_State {
	if voice.gate {
		return ADSR_State.ATTACK
	}

	release_samples := release_seconds * sample_rate

	release_multiplier := math.exp(-6.91 / release_samples)
	release_target := -0.001

	voice.current_amplitude =
		release_target + (voice.current_amplitude - release_target) * release_multiplier

	if voice.current_amplitude <= 0.0 {
		voice.current_amplitude = 0.0
		return ADSR_State.IDLE
	}

	return ADSR_State.RELEASE
}
