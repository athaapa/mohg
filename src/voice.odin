package mohg

import "core:math"

Oscillator :: struct {
	phase: f64,
	pan:   f64,
	drift: f64,
}

Voice :: struct {
	note:                u8,
	gate:                bool,
	state:               ADSR_State,
	current_amplitude:   f64,
	left_ladder_filter:  Ladder_Filter,
	right_ladder_filter: Ladder_Filter,
	frequency:           f64,
	oscillators:         [16]Oscillator,
}

Voices :: struct {
	voices:      [128]Voice,
	voice_count: u8,
}

note_on :: proc "c" (voices: ^Voices, max_voices: u8, note: u8) -> (^Voice, bool) {
	voice: ^Voice
	if (voices.voice_count < max_voices) {
		voice = &voices.voices[voices.voice_count]
		voice^ = Voice {
			note      = note,
			gate      = true,
			state     = ADSR_State.IDLE,
			frequency = 440.0 * math.pow(2.0, (f64(note) - 69.0) / 12.0),
		}
		voices.voice_count += 1
		return voice, false
	} else {
		cur_voice := voices.voices[0]

		for i in 0 ..< int(voices.voice_count) - 1 {
			voices.voices[i] = voices.voices[i + 1]
		}

		cur_voice.frequency = 440.0 * math.pow(2.0, (f64(note) - 69.0) / 12.0)
		cur_voice.note = note
		cur_voice.gate = true

		voices.voices[voices.voice_count - 1] = cur_voice
		voice = &voices.voices[voices.voice_count - 1]
		return voice, true
	}
}

note_off :: proc "c" (voices: ^Voices, note: u8) {
	for i in 0 ..< voices.voice_count {
		voice := &voices.voices[i]
		if voice.note == note && voice.gate {
			voice.gate = false
			break
		}
	}
}

voice_remove :: proc "contextless" (voices: ^Voices, index: u8) {
	last := voices.voice_count - 1
	for j in index ..< last {
		voices.voices[j] = voices.voices[j + 1]
	}
	voices.voices[last] = {}
	voices.voice_count -= 1
}
