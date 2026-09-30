package mohg

// MIDI event transport: the event type that crosses from the CoreMIDI
// thread to the audio thread.

MIDI_QUEUE_CAPACITY :: 64

Midi_Note_On :: struct {
	channel, note, velocity: u8,
}
Midi_Note_Off :: struct {
	channel, note, velocity: u8,
}
Midi_CC :: struct {
	channel, number, value: u8,
}

Midi_Event :: union {
	Midi_Note_On,
	Midi_Note_Off,
	Midi_CC,
}
