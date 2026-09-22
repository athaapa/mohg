package mohg

// Entry point: allocates the long-lived objects, wires them into the
// engine, starts MIDI and audio, and reports metrics on exit.

import "core:fmt"
import "core:os"

main :: proc() {
	timebase: Mach_Timebase_Info

	status := mach_timebase_info(&timebase)
	if status != 0 {
		panic("mach_timebase_info failed")
	}

	voices := Voices{}

	synth := Synth {
		sample_rate = 48_000,
		adsr_config = ADSR_Config {
			attack_seconds = 0.05,
			decay_seconds = 0.25,
			sustain_level = 1,
			release_seconds = 0.1,
		},
		ladder_filter = Ladder_Filter{},
		voices = &voices,
	}

	midi: Midi_Input
	midi_event_queue := Spsc_Queue(Midi_Event, MIDI_QUEUE_CAPACITY){}
	parameter_event_queue := Spsc_Queue(Parameter_Event, PARAMETER_QUEUE_CAPACITY){}
	log_queue := Log_Queue{}

	engine := Engine {
		synth                 = synth,
		midi_event_queue      = &midi_event_queue,
		parameter_event_queue = &parameter_event_queue,
		log_queue             = &log_queue,
	}

	status = midi_input_init(&midi, &midi_event_queue)
	if (status != 0) {
		panic("failed to initalize midi")
	}

	unit: AudioUnit
	audio_init(&engine, &unit)
	render_metrics_init(&engine.render_metrics, timebase, engine.synth.sample_rate)

	ladder_filter_set_sample_rate(&engine.synth.ladder_filter, f32(engine.synth.sample_rate))
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
	log_drain(engine.log_queue)
	render_metrics_print(&engine.render_metrics)
}
