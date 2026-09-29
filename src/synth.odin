package mohg

import "core:math"
ADSR_Config :: struct {
	attack_seconds:  f64,
	decay_seconds:   f64,
	sustain_level:   f64,
	release_seconds: f64,
}

Synth :: struct {
	sample_rate:   f64,
	adsr_config:   ADSR_Config,
	ladder_filter: Ladder_Filter,
	max_voices:    u8,
	voices:        ^Voices,
	unison_count:  u8,
	detune_cents:  f64,
}

synth_process_midi :: proc "contextless" (
	synth: ^Synth,
	queue: ^Spsc_Queue(Midi_Event, MIDI_QUEUE_CAPACITY),
) {
	for {
		event, ok := spsc_try_pop(queue)
		if !ok {
			break
		}

		switch event.kind {
		case .Note_On:
			{
				voice, stolen := note_on(synth.voices, synth.max_voices, event.note)
				if (!stolen) {
					voice.left_ladder_filter = synth.ladder_filter
					voice.right_ladder_filter = synth.ladder_filter
					ladder_filter_reset(&voice.left_ladder_filter)
					ladder_filter_reset(&voice.right_ladder_filter)
				}
			}
		case .Note_Off:
			{
				note_off(synth.voices, event.note)
			}
		}
	}
}

synth_render :: proc "contextless" (
	synth: ^Synth,
	voices: ^Voices,
	samples: [^]f32,
	frame_count: int,
	channel_count: int,
) {

	for frame in 0 ..< frame_count {
		left_sample: f32
		right_sample: f32

		voice_idx: u8
		for voice_idx < voices.voice_count {
			voice := &voices.voices[voice_idx]

			osc_idx: u8

			audible := voice.current_amplitude > 0

			left_voice_sample: f32
			right_voice_sample: f32
			for osc_idx < synth.unison_count {
				// update phase based on frequency
				detune: f64
				pan: f64
				pan_angle := (pan + 1) * math.PI / 4

				if synth.unison_count > 1 {
					detune =
						-synth.detune_cents +
						f64(osc_idx) *
							(f64(2.0 * synth.detune_cents) / f64(synth.unison_count - 1))

					pan = -1 * (-1 + f64(2.0 * osc_idx) / f64(synth.unison_count - 1))
					pan_angle = (pan + 1) * math.PI / 4
				}

				left_gain := math.cos(pan_angle)
				right_gain := math.sin(pan_angle)

				drift := f64(0)
				freq := voice.frequency * cents_to_freq_multiplier(detune + drift)
				phase_step := freq / synth.sample_rate

				// update the sample
				osc := &voice.oscillators[osc_idx]
				osc_sample :=
					0.2 * voice.current_amplitude * generate_triangle_wave(osc.phase, phase_step)

				left_voice_sample += f32(left_gain * osc_sample)
				right_voice_sample += f32(right_gain * osc_sample)

				if audible {
					osc.phase += phase_step
					if osc.phase >= 1 {
						osc.phase -= 1
					}
				}

				osc_idx += 1
			}

			left_voice_sample /= f32(synth.unison_count)
			right_voice_sample /= f32(synth.unison_count)

			/*
			left_voice_sample = ladder_filter_process(&voice.left_ladder_filter, left_voice_sample)
			right_voice_sample = ladder_filter_process(
				&voice.right_ladder_filter,
				right_voice_sample,
			)
            */

			new_state: ADSR_State
			switch voice.state {
			case ADSR_State.IDLE:
				new_state = on_idle(synth, voice)
			case ADSR_State.ATTACK:
				new_state = on_attack(synth, voice)
			case ADSR_State.DECAY:
				new_state = on_decay(synth, voice)
			case ADSR_State.SUSTAIN:
				new_state = on_sustain(synth, voice)
			case ADSR_State.RELEASE:
				new_state = on_release(synth, voice)
			}

			voice.state = new_state

			if voice.state == ADSR_State.IDLE && !voice.gate {
				voice_remove(voices, voice_idx)
				continue
			}

			left_sample += left_voice_sample
			right_sample += right_voice_sample

			voice_idx += 1
		}

		samples[frame * 2] = left_sample
		samples[frame * 2 + 1] = right_sample
	}
}
