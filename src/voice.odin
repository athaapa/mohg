package mohg

import "core:math"
// Voice pool: fixed storage for sounding voices plus note on/off bookkeeping.
// A voice outlives its key: note_off clears the gate and the voice stays in
// the pool until its envelope returns to IDLE.

Voice :: struct {
	note:              u8,
	gate:              bool,
	state:             ADSR_State,
	current_amplitude: f64,
	phase:             f64,
	ladder_filter:     Ladder_Filter,
	frequency:         f64,
}

Voices :: struct {
	voices:      [128]Voice,
	voice_count: u8,
}

// TODO: consider the edge case of when a note is held multiple times or the capacity somehow gets overflowed
note_on :: proc "c" (voices: ^Voices, note: u8) -> ^Voice {
	voice := &voices.voices[voices.voice_count]
	voice^ = Voice {
		note      = note,
		gate      = true,
		state     = ADSR_State.IDLE,
		frequency = 440.0 * math.pow(2.0, (f64(note) - 69.0) / 12.0),
	}
	voices.voice_count += 1
	return voice
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
