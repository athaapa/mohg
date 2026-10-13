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

				for i in 0 ..< synth.unison_count {
					voice.oscillators[i].phase = f64(random_f64(&synth.rng))
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
						drive = min(LADDER_MIN_DRIVE, LADDER_MAX_DRIVE * f64(e.value) / 127),
					}

					_ = spsc_try_push(parameter_queue, param_event)
				}

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

		for i in 0 ..< synth.oversampling_factor {
			left: f64
			right: f64

			voice_idx: u8
			for voice_idx < voices.voice_count {
				voice := &voices.voices[voice_idx]

				audible := voice.current_amplitude > 0

				left_voice_sample: f64
				right_voice_sample: f64

				for osc_idx in 0 ..< synth.unison_count {
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
					phase_step := freq / (synth.sample_rate * f64(synth.oversampling_factor))

					// update the sample
					osc := &voice.oscillators[osc_idx]

					wave: f64
					switch synth.waveform {
					case Waveform.SINE:
						wave = generate_sine_wave(osc.phase)
					case Waveform.SAW:
						wave = generate_saw_wave(osc.phase, phase_step)
					case Waveform.SQUARE:
						wave = generate_square_wave(osc.phase, phase_step)
					case Waveform.TRIANGLE:
						wave = generate_triangle_wave(osc.phase, phase_step)
					}

					// TODO: Volume control
					osc_sample := 0.4 * voice.current_amplitude * wave

					left_voice_sample += left_gain * osc_sample
					right_voice_sample += right_gain * osc_sample

					// only advance phase if audible
					if audible {
						osc.phase += phase_step
						if osc.phase >= 1 {
							osc.phase -= 1
						}
					}
				}

				left_voice_sample /= f64(synth.unison_count)
				right_voice_sample /= f64(synth.unison_count)

				left_voice_sample = ladder_filter_process(
					&voice.left_ladder_filter,
					left_voice_sample,
				)

				right_voice_sample = ladder_filter_process(
					&voice.right_ladder_filter,
					right_voice_sample,
				)

				left += left_voice_sample
				right += right_voice_sample

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

				if new_state == .RELEASE && voice.state != .RELEASE {
					telemetry_emit(
						synth.telemetry,
						Telemetry_Record {
							kind = .RELEASE_STARTED,
							frame = synth.rendered_frames + u64(frame),
							subframe = u8(i),
							voice_id = voice.telemetry_id,
							note = voice.note,
							amplitude = voice.current_amplitude,
							left = left_voice_sample,
							right = right_voice_sample,
						},
					)
				}
				voice.state = new_state

				if voice.state == ADSR_State.IDLE && !voice.gate {
					telemetry_emit(
						synth.telemetry,
						Telemetry_Record {
							kind = .VOICE_REMOVED,
							frame = synth.rendered_frames + u64(frame),
							subframe = u8(i),
							voice_id = voice.telemetry_id,
							note = voice.note,
							amplitude = voice.current_amplitude,
							left = left_voice_sample,
							right = right_voice_sample,
						},
					)
					voice_remove(voices, voice_idx)
					continue
				}


				voice_idx += 1
			}

			decimator_push(&synth.left_decimator, left)
			decimator_push(&synth.right_decimator, right)

			left = decimator_output(&synth.left_decimator)
			right = decimator_output(&synth.right_decimator)

			if (i == synth.oversampling_factor - 1) {
				left_sample = f32(left)
				right_sample = f32(right)
			}
		}

		samples[frame * 2] = left_sample
		samples[frame * 2 + 1] = right_sample
	}
	synth.rendered_frames += u64(frame_count)
}
