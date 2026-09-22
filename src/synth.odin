package mohg

// Synth: the instrument. Owns the patch (ADSR config, template filter),
// reacts to MIDI events, and renders voices into a sample buffer.

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
	max_voices:    i32,
	voices:        ^Voices,
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
				voice := note_on(synth.voices, event.note)
				voice.ladder_filter = synth.ladder_filter
				ladder_filter_reset(&voice.ladder_filter)
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
		sample: f32

		voice_index: u8
		for voice_index < voices.voice_count {
			voice := &voices.voices[voice_index]

			phase_step := voice.frequency / synth.sample_rate

			voice_sample := f32(0.2 * voice.current_amplitude * generate_saw_wave(voice.phase))
			voice_sample = ladder_filter_process(&voice.ladder_filter, voice_sample)
			sample += voice_sample

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
				voice_remove(voices, voice_index)
				continue
			}

			if voice.current_amplitude > 0 {
				voice.phase += phase_step
				if voice.phase >= 1 {
					voice.phase -= 1
				}
			}

			voice_index += 1
		}


		for channel in 0 ..< channel_count {
			samples[frame * channel_count + channel] = sample
		}
	}
}
