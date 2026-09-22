package mohg

// MIDI event transport: the event type that crosses from the CoreMIDI
// thread to the audio thread.

MIDI_QUEUE_CAPACITY :: 64

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
