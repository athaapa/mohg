package mohg
import "core:testing"

@(test)
note_on_produces_audio :: proc(t: ^testing.T) {
	sample_rate :: 48_000.0
	frame_count :: 4_800
	synth := Synth {
		sample_rate = sample_rate,
		adsr_config = ADSR_Config {
			attack_seconds = 0.05,
			decay_seconds = 0.25,
			sustain_level = 1,
			release_seconds = 0.1,
		},
	}
	ladder_filter_set_sample_rate(&synth.ladder_filter, f32(sample_rate))
	ladder_filter_set_parameters(&synth.ladder_filter, 1_000, 0.6)
	voices := Voices{}
	synth.voices = &voices
	queue := Spsc_Queue(Midi_Event, MIDI_QUEUE_CAPACITY){}
	pushed := spsc_try_push(&queue, Midi_Event{kind = .Note_On, note = 69, velocity = 100})
	testing.expect(t, pushed, "midi queue accepted the note")
	synth_process_midi(&synth, &queue)
	if !testing.expect_value(t, voices.voice_count, 1) {
		return
	}
	testing.expect_value(t, voices.voices[0].note, 69)
	samples: [frame_count]f32
	synth_render(&synth, &voices, raw_data(samples[:]), frame_count, 1)
	voice := voices.voices[0]
	testing.expect(t, voice.gate == true)
	testing.expect_value(t, voice.state, ADSR_State.SUSTAIN)

	if !testing.expect(t, voice.current_amplitude > 0, "amplitude advanced on the stored voice") {
		return
	}
	testing.expect(t, voice.state != .IDLE, "envelope left idle")
	peak: f32
	for sample in samples {
		peak = max(peak, abs(sample))
	}
	testing.expect(t, peak > 0, "buffer is non-silent")
}
