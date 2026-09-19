package mohg

import "core:math"

ADSR_Config :: struct {
	state:           ADSR_State,
	attack_seconds:  f64,
	decay_seconds:   f64,
	sustain_level:   f64,
	release_seconds: f64,
}

Synth :: struct {
	phase:             f64,
	frequency:         f64,
	sample_rate:       f64,
	gate:              bool,
	current_amplitude: f64,
	adsr_config:       ADSR_Config,
}


// TODO: consider the edge case of when a note is held multiple times or the capacity somehow gets overflowed
note_on :: proc "c" (held_notes: ^Held_Notes, note: u8) {
	held_notes.held[held_notes.held_count].value = note
	held_notes.held_count += 1
}

note_off :: proc "c" (held_notes: ^Held_Notes, note: u8) {
	held := &held_notes.held
	held_count := &held_notes.held_count

	for i in 0 ..< held_notes.held_count {
		if held[i].value == note {
			for j in i ..< held_count^ - 1 {
				held[j] = held[j + 1]
			}
			held_count^ -= 1
			break
		}
	}
}

synth_render :: proc "contextless" (
	synth: ^Synth,
	samples: [^]f32,
	frame_count: int,
	channel_count: int,
) {
	phase_step := synth.frequency / synth.sample_rate

	for frame in 0 ..< frame_count {
		sample := f32(0.2 * synth.current_amplitude * math.sin(2 * math.PI * synth.phase))

		new_state: ADSR_State
		switch synth.adsr_config.state {
		case ADSR_State.IDLE:
			new_state = on_idle(synth)
		case ADSR_State.ATTACK:
			new_state = on_attack(synth)
		case ADSR_State.DECAY:
			new_state = on_decay(synth)
		case ADSR_State.SUSTAIN:
			new_state = on_sustain(synth)
		case ADSR_State.RELEASE:
			new_state = on_release(synth)
		}

		synth.adsr_config.state = new_state


		if synth.current_amplitude > 0 {
			synth.phase += phase_step
			if synth.phase >= 1 {
				synth.phase -= 1
			}
		}


		for channel in 0 ..< channel_count {
			samples[frame * channel_count + channel] = sample
		}
	}
}

render :: proc "c" (
	inRefCon: rawptr,
	ioActionFlags: ^AudioUnitRenderActionFlags,
	inTimeStamp: ^AudioTimeStamp,
	inBusNumber: u32,
	inNumberFrames: u32,
	ioData: ^AudioBufferList,
) -> OSStatus {
	engine := cast(^Engine)inRefCon
	synth := &engine.synth

	midi_data := engine.midi_data

	queue := midi_data.midi_events
	held_notes := midi_data.held_notes

	buffer := &ioData.mBuffers[0]
	samples := cast([^]f32)buffer.mData
	channel_count := int(buffer.mNumberChannels)

	for {
		event, ok := midi_queue_try_pop(queue)
		if !ok {
			break
		}

		switch event.kind {
		case .Note_On:
			{
				note_on(held_notes, event.note)
			}
		case .Note_Off:
			{
				note_off(held_notes, event.note)
			}
		}
	}

	if (held_notes.held_count > 0) {
		synth.frequency =
			440.0 *
			math.pow(2.0, (f64(held_notes.held[held_notes.held_count - 1].value) - 69.0) / 12.0)
		synth.gate = true
	} else {
		synth.gate = false
	}


	synth_render(synth, samples, int(inNumberFrames), channel_count)

	return 0
}
