package mohg

import "core:math"
MIDI_QUEUE_CAPACITY :: 64
MIDI_QUEUE_MASK :: u64(MIDI_QUEUE_CAPACITY - 1)

Midi_Event_Kind :: enum u8 {
	Note_On,
	Note_Off,
}

Midi_Event :: struct {
	kind:     Midi_Event_Kind,
	channel:  u8,
	note:     u8,
	velocity: u8,
}

process_midi_events :: proc "contextless" (
	synth: ^Synth,
	queue: ^Spsc_Queue(Midi_Event, MIDI_QUEUE_CAPACITY),
	held_notes: ^Held_Notes,
) {
	for {
		event, ok := spsc_try_pop(queue)
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
}
