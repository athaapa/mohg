package mohg

import "core:fmt"
import "core:os"

Note :: struct {
	value: u8,
}

Held_Notes :: struct {
	held:       [128]Note,
	held_count: u8,
}

Midi_Data :: struct {
	midi_event_queue: ^Spsc_Queue(Midi_Event, MIDI_QUEUE_CAPACITY),
	held_notes:       ^Held_Notes,
}

Parameter_Data :: struct {
	parameter_event_queue: ^Spsc_Queue(Parameter_Event, PARAMETER_QUEUE_CAPACITY),
}

Engine :: struct {
	synth:          Synth,
	midi_data:      ^Midi_Data,
	parameter_data: ^Parameter_Data,
	render_metrics: Render_Metrics,
}

main :: proc() {
	timebase: Mach_Timebase_Info

	status := mach_timebase_info(&timebase)
	if status != 0 {
		panic("mach_timebase_info failed")
	}

	synth := Synth {
		frequency = 440,
		sample_rate = 48_000,
		adsr_config = ADSR_Config {
			state = ADSR_State.IDLE,
			attack_seconds = 0.05,
			decay_seconds = 0.25,
			sustain_level = 1,
			release_seconds = 0.1,
		},
		ladder_filter = Ladder_Filter{},
	}

	midi: Midi_Input
	midi_events := Spsc_Queue(Midi_Event, MIDI_QUEUE_CAPACITY){}
	held: [128]Note

	held_notes := Held_Notes {
		held       = held,
		held_count = 0,
	}

	midi_data := Midi_Data {
		midi_event_queue = &midi_events,
		held_notes       = &held_notes,
	}

	parameter_events := Spsc_Queue(Parameter_Event, PARAMETER_QUEUE_CAPACITY){}

	parameter_data := Parameter_Data {
		parameter_event_queue = &parameter_events,
	}

	engine := Engine {
		synth          = synth,
		midi_data      = &midi_data,
		parameter_data = &parameter_data,
	}

	status = midi_input_init(&midi, &midi_data)
	if (status != 0) {
		panic("failed to initalize midi")
	}


	unit: AudioUnit
	audio_init(&engine, &unit)
	render_metrics_init(&engine.render_metrics, timebase, engine.synth.sample_rate)

	ladder_filter_set_sample_rate(&engine.synth.ladder_filter, f32(synth.sample_rate))
	ladder_filter_set_parameters(&engine.synth.ladder_filter, 1_000, 0.6)

	// start
	status = AudioOutputUnitStart(unit)
	if (status != 0) {
		panic("failed to start audio unit")
	}


	fmt.println("Press Enter to exit")
	input: [1]byte
	_, _ = os.read(os.stdin, input[:])


	audio_destroy(&unit)
	render_metrics_print(&engine.render_metrics)
}
