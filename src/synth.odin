package mohg

import "core:math"

ADSR_Config :: struct {
	attack_seconds:  f64,
	decay_seconds:   f64,
	sustain_level:   f64,
	release_seconds: f64,
}

Waveform :: enum {
	SINE,
	SAW,
	SQUARE,
	TRIANGLE,
}

Synth :: struct {
	telemetry:           ^Telemetry,
	rendered_frames:     u64,
	next_voice_id:       u64,
	sample_rate:         f64,
	adsr_config:         ADSR_Config,
	ladder_filter:       Ladder_Filter,
	max_voices:          u8,
	voices:              ^Voices,
	unison_count:        u8,
	detune_cents:        f64,
	rng:                 RNG,
	waveform:            Waveform,
	oversampling_factor: u8,
	left_decimator:      Decimator,
	right_decimator:     Decimator,
	analog:              Analog_Config,
	drift_coeff:         f64,
	drift_noise_gain:    f64,
}

Analog_Config :: struct {
	voice_tune_spread_cents: f64,
	voice_cutoff_spread:     f64,
	voice_resonance_spread:  f64,
	osc_tune_spread_cents:   f64,
	drift_rms_cents:         f64,
	drift_rate_hz:           f64,
}

Stereo64 :: [2]f64
Stereo32 :: [2]f32

CENTS_TO_LINEAR :: math.LN2 / 1200.0

synth_update_drift_coefficients :: proc "contextless" (synth: ^Synth) {
	if synth.sample_rate <= 0 || synth.analog.drift_rate_hz <= 0 {
		synth.drift_coeff = 0
		synth.drift_noise_gain = 0
		return
	}
	a := 1.0 - math.exp(-math.TAU * synth.analog.drift_rate_hz / synth.sample_rate)
	synth.drift_coeff = a
	// uniform noise in [-1, 1] has variance 1/3; a one-pole scales variance by a / (2 - a)
	synth.drift_noise_gain = synth.analog.drift_rms_cents / math.sqrt(a / (2.0 - a) / 3.0)
}

voice_apply_filter_parameters :: proc "contextless" (synth: ^Synth, voice: ^Voice) {
	cutoff_hz := synth.ladder_filter.cutoff_hz * voice.cutoff_mult
	resonance := synth.ladder_filter.resonance + voice.resonance_offset
	drive := synth.ladder_filter.drive
	ladder_filter_set_parameters(&voice.left_ladder_filter, cutoff_hz, resonance, drive)
	ladder_filter_set_parameters(&voice.right_ladder_filter, cutoff_hz, resonance, drive)
}

oscillator_update_drift :: proc "contextless" (
	osc: ^Oscillator,
	rng: ^RNG,
	drift_coeff: f64,
	drift_noise_gain: f64,
) {
	noise := random_bipolar(rng) * drift_noise_gain
	osc.drift += drift_coeff * (noise - osc.drift)
	osc.phase_step = osc.base_step * (1.0 + osc.drift * CENTS_TO_LINEAR)
}

synth_process_midi :: proc "contextless" (
	synth: ^Synth,
	midi_queue: ^Spsc_Queue(Midi_Event, MIDI_QUEUE_CAPACITY),
	parameter_queue: ^Spsc_Queue(Parameter_Event, PARAMETER_QUEUE_CAPACITY),
) {
	for {
		event, ok := spsc_try_pop(midi_queue)
		if !ok {
			break
		}

		switch e in event {
		case Midi_Note_On:
			{
				voice, stolen := note_on(synth.voices, synth.max_voices, e.note)
				synth.next_voice_id += 1
				voice.telemetry_id = synth.next_voice_id
				telemetry_emit(
					synth.telemetry,
					Telemetry_Record {
						kind = .NOTE_ON,
						frame = synth.rendered_frames,
						voice_id = voice.telemetry_id,
						note = voice.note,
						stolen = stolen,
						amplitude = voice.current_amplitude,
					},
				)
				if (!stolen) {
					voice.left_ladder_filter = synth.ladder_filter
					voice.right_ladder_filter = synth.ladder_filter
					ladder_filter_reset(&voice.left_ladder_filter)
					ladder_filter_reset(&voice.right_ladder_filter)
				}

				analog := synth.analog
				voice.tune_cents = random_bipolar(&synth.rng) * analog.voice_tune_spread_cents
				voice.cutoff_mult = 1.0 + random_bipolar(&synth.rng) * analog.voice_cutoff_spread
				voice.resonance_offset = random_bipolar(&synth.rng) * analog.voice_resonance_spread
				voice_apply_filter_parameters(synth, voice)


				oversampled_rate := synth.sample_rate * f64(synth.oversampling_factor)

				for osc_idx in 0 ..< synth.unison_count {
					osc := &voice.oscillators[osc_idx]
					spread := unison_spread_position(osc_idx, synth.unison_count)

					osc.phase = random_f64(&synth.rng)
					osc.static_cents = random_bipolar(&synth.rng) * analog.osc_tune_spread_cents
					osc.drift = random_bipolar(&synth.rng) * analog.drift_rms_cents
					osc.detune = spread * synth.detune_cents
					oscillator_set_pan(osc, -spread)

					cents := voice.tune_cents + osc.detune + osc.static_cents
					oscillator_set_frequency(
						osc,
						voice.frequency * cents_to_freq_multiplier(cents),
						oversampled_rate,
					)

					oscillator_update_drift(
						osc,
						&synth.rng,
						synth.drift_coeff,
						synth.drift_noise_gain,
					)

				}

			}
		case Midi_Note_Off:
			{
				note_off(synth.voices, e.note)
			}
		case Midi_CC:
			{
				if (e.number == 74) { 	// cutoff
					t := f64(e.value) / 127
					param_event := Ladder_Filter_Cutoff_Event {
						cutoff_hz = LADDER_MIN_CUTOFF * math.pow(
							(LADDER_MAX_CUTOFF / LADDER_MIN_CUTOFF),
							t,
						),
					}

					_ = spsc_try_push(parameter_queue, param_event)
				} else if (e.number == 71) { 	// resonance
					param_event := Ladder_Filter_Resonance_Event {
						resonance = f64(e.value) / 127,
					}

					_ = spsc_try_push(parameter_queue, param_event)
				} else if (e.number == 76) { 	// drive
					param_event := Ladder_Filter_Drive_Event {
						drive = max(LADDER_MIN_DRIVE, LADDER_MAX_DRIVE * f64(e.value) / 127),
					}

					_ = spsc_try_push(parameter_queue, param_event)
				}

			}
		}
	}
}

unison_spread_position :: proc "contextless" (osc_idx: u8, unison_count: u8) -> f64 {
	if unison_count <= 1 do return 0
	return -1 + 2 * f64(osc_idx) / f64(unison_count - 1)
}

oscillator_set_pan :: proc "contextless" (osc: ^Oscillator, pan: f64) {
	osc.pan = pan
	osc.pan_angle = (pan + 1) * math.PI / 4
	osc.left_gain = math.cos(osc.pan_angle)
	osc.right_gain = math.sin(osc.pan_angle)
}

oscillator_set_frequency :: proc "contextless" (
	osc: ^Oscillator,
	freq: f64,
	oversampled_rate: f64,
) {
	osc.freq = freq
	osc.base_step = freq / oversampled_rate
	osc.phase_step = osc.base_step
}

oscillator_render :: proc "contextless" (osc: ^Oscillator, waveform: Waveform) -> Stereo64 {
	left_osc_sample: f64
	right_osc_sample: f64

	wave: f64

	switch waveform {
	case Waveform.SINE:
		wave = generate_sine_wave(osc.phase)
	case Waveform.SAW:
		wave = generate_saw_wave(osc.phase, osc.phase_step)
	case Waveform.SQUARE:
		wave = generate_square_wave(osc.phase, osc.phase_step)
	case Waveform.TRIANGLE:
		wave = generate_triangle_wave(osc.phase, osc.phase_step)
	}
	osc_sample := 0.4 * wave

	left_osc_sample += osc.left_gain * osc_sample
	right_osc_sample += osc.right_gain * osc_sample

	return Stereo64{left_osc_sample, right_osc_sample}
}

oscillator_advance_phase :: proc "contextless" (osc: ^Oscillator) {
	osc.phase += osc.phase_step
	if osc.phase >= 1 {
		osc.phase -= 1
	}
}

apply_noise :: proc "contextless" (sample: Stereo64, rng: ^RNG) -> Stereo64 {
	left_sample := sample[0]
	right_sample := sample[1]

	left_noise := 0.005 * (2.0 * random_f64(rng) - 1.0)
	right_noise := 0.005 * (2.0 * random_f64(rng) - 1.0)

	left_sample += left_noise
	right_sample += right_noise

	return Stereo64{left_sample, right_sample}
}

saturate_samples :: proc "contextless" (sample: Stereo64, drive: f64) -> Stereo64 {
	left_sample := fast_tanh(drive * sample[0]) / drive
	right_sample := fast_tanh(drive * sample[1]) / drive

	return Stereo64{left_sample, right_sample}
}

voice_update_adsr :: proc "contextless" (
	voice: ^Voice,
	sample_rate: f64,
	adsr_config: ADSR_Config,
) {
	new_state: ADSR_State
	switch voice.state {
	case ADSR_State.IDLE:
		new_state = on_idle(voice)
	case ADSR_State.ATTACK:
		new_state = on_attack(voice, sample_rate, adsr_config.attack_seconds)
	case ADSR_State.DECAY:
		new_state = on_decay(
			voice,
			sample_rate,
			adsr_config.sustain_level,
			adsr_config.decay_seconds,
		)
	case ADSR_State.SUSTAIN:
		new_state = on_sustain(voice)
	case ADSR_State.RELEASE:
		new_state = on_release(voice, sample_rate, adsr_config.release_seconds)
	}

	/*
	if new_state == .RELEASE && voice.state != .RELEASE {
		telemetry_emit(
			telemetry,
			Telemetry_Record {
				kind = .RELEASE_STARTED,
				frame = synth.rendered_frames + u64(frame),
				voice_id = voice.telemetry_id,
				note = voice.note,
				amplitude = voice.current_amplitude,
				left = f64(left_sample),
				right = f64(right_sample),
			},
		)
	}
    */
	voice.state = new_state
}

apply_ladder_filter :: proc "contextless" (
	sample: Stereo64,
	left_ladder_filter: ^Ladder_Filter,
	right_ladder_filter: ^Ladder_Filter,
) -> Stereo64 {
	left_voice_sample := ladder_filter_process(left_ladder_filter, sample[0])
	right_voice_sample := ladder_filter_process(right_ladder_filter, sample[1])

	return Stereo64{left_voice_sample, right_voice_sample}

}

push_decimator :: proc "contextless" (
	sample: Stereo64,
	left_decimator: ^Decimator,
	right_decimator: ^Decimator,
) {
	decimator_push(left_decimator, sample[0])
	decimator_push(right_decimator, sample[1])
}

apply_decimator :: proc "contextless" (
	sample: Stereo64,
	left_decimator: ^Decimator,
	right_decimator: ^Decimator,
) -> Stereo64 {

	return Stereo64{decimator_output(left_decimator), decimator_output(right_decimator)}
}

synth_render :: proc "contextless" (
	synth: ^Synth,
	samples: [^]f32,
	frame_count: int,
	channel_count: int,
) {
	voices := synth.voices
	for frame in 0 ..< frame_count {
		sample: Stereo32

		for voice_idx in 0 ..< voices.voice_count {
			for osc_idx in 0 ..< synth.unison_count {
				oscillator_update_drift(
					&voices.voices[voice_idx].oscillators[osc_idx],
					&synth.rng,
					synth.drift_coeff,
					synth.drift_noise_gain,
				)
			}
		}

		for i in 0 ..< synth.oversampling_factor {
			oversample: Stereo64

			voice_idx: u8
			for voice_idx < voices.voice_count {
				voice := &voices.voices[voice_idx]

				audible := voice.current_amplitude > 0

				voice_sample: Stereo64

				for osc_idx in 0 ..< synth.unison_count {
					osc := &voice.oscillators[osc_idx]

					voice_sample += oscillator_render(osc, synth.waveform)

					if audible {
						oscillator_advance_phase(osc)
					}
				}


				voice_sample /= f64(synth.unison_count)

				// TODO: Make this constant
				mix_drive := 2.0

				voice_sample = saturate_samples(voice_sample, mix_drive)

				voice_sample = apply_noise(voice_sample, &synth.rng)

				voice_sample = apply_ladder_filter(
					voice_sample,
					&voice.left_ladder_filter,
					&voice.right_ladder_filter,
				)

				oversample += (voice_sample * voice.current_amplitude)

				voice_idx += 1
			}

			push_decimator(oversample, &synth.left_decimator, &synth.right_decimator)

			oversample = apply_decimator(
				oversample,
				&synth.left_decimator,
				&synth.right_decimator,
			)

			if (i == synth.oversampling_factor - 1) {

				sample = cast([2]f32)(oversample)
			}
		}

		// TODO: Volume control

		voice_idx: u8

		for voice_idx < voices.voice_count {
			voice := &voices.voices[voice_idx]

			voice_update_adsr(voice, synth.sample_rate, synth.adsr_config)

			if voice.state == ADSR_State.IDLE && !voice.gate {
				/*
				telemetry_emit(
					synth.telemetry,
					Telemetry_Record {
						kind = .VOICE_REMOVED,
						frame = synth.rendered_frames + u64(frame),
						voice_id = voice.telemetry_id,
						note = voice.note,
						amplitude = voice.current_amplitude,
						left = f64(left_sample),
						right = f64(right_sample),
					},
				)
                */
				voice_remove(voices, voice_idx)
				continue
			}

			voice_idx += 1

		}

		samples[frame * 2] = sample[0]
		samples[frame * 2 + 1] = sample[1]
	}
	synth.rendered_frames += u64(frame_count)
}
