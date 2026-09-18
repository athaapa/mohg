package mohg

import "core:time"

Note :: struct {
	value: u8,
}

Held_Notes :: struct {
	held:       [128]Note,
	held_count: u8,
}

Midi_Data :: struct {
	midi_events: ^Midi_Event_Queue,
	held_notes:  ^Held_Notes,
}

Engine :: struct {
	synth:     Synth,
	midi_data: ^Midi_Data,
}

main :: proc() {
	synth := Synth {
		frequency   = 440,
		sample_rate = 48_000,
	}

	midi: Midi_Input
	midi_events := Midi_Event_Queue{}
	held: [128]Note

	held_notes := Held_Notes {
		held       = held,
		held_count = 0,
	}

	midi_data := Midi_Data {
		midi_events = &midi_events,
		held_notes  = &held_notes,
	}

	engine := Engine {
		synth     = synth,
		midi_data = &midi_data,
	}

	status := midi_input_init(&midi, &midi_data)
	if (status != 0) {
		panic("failed to initalize midi")
	}

	unit: AudioUnit
	audio_init(&engine, &unit)

	time.sleep(30 * time.Second)
}
