package mohg

// Entry point: allocates the long-lived objects, wires them into the
// engine, starts MIDI and audio, and reports metrics on exit.

import "base:intrinsics"
import "core:fmt"
import "core:os"
import "core:thread"

main :: proc() {
	timebase: Mach_Timebase_Info

	status := mach_timebase_info(&timebase)
	if status != 0 {
		panic("mach_timebase_info failed")
	}

	voices := Voices{}
	telemetry := Telemetry{}

	synth := Synth {
		telemetry = &telemetry,
		sample_rate = 48_000,
		adsr_config = ADSR_Config {
			attack_seconds = 0.15,
			decay_seconds = 0.25,
			sustain_level = 1,
			release_seconds = 0.15,
		},
		ladder_filter = Ladder_Filter{},
		voices = &voices,
		max_voices = 4,
		unison_count = 5,
		detune_cents = 15,
		rng = RNG{state = 1},
		waveform = Waveform.SQUARE,
		oversampling_factor = 1,
		left_decimator = Decimator{},
		right_decimator = Decimator{},
	}

	midi: Midi_Input
	midi_event_queue := Spsc_Queue(Midi_Event, MIDI_QUEUE_CAPACITY){}
	parameter_event_queue := Spsc_Queue(Parameter_Event, PARAMETER_QUEUE_CAPACITY){}

	engine := Engine {
		synth                 = synth,
		midi_event_queue      = &midi_event_queue,
		parameter_event_queue = &parameter_event_queue,
	}

	status = midi_input_init(&midi, &midi_event_queue)
	if (status != 0) {
		panic("failed to initalize midi")
	}

	unit: AudioUnit
	audio_init(&engine, &unit)

	ladder_filter_set_sample_rate(
		&engine.synth.ladder_filter,
		engine.synth.sample_rate * f64(engine.synth.oversampling_factor),
	)
	ladder_filter_set_parameters(&engine.synth.ladder_filter, 10_000, 0, 2)

	decimator_init(&engine.synth.left_decimator, synth.oversampling_factor, synth.sample_rate)
	decimator_init(&engine.synth.right_decimator, synth.oversampling_factor, synth.sample_rate)

	// start
	status = AudioOutputUnitStart(unit)
	if (status != 0) {
		panic("failed to start audio unit")
	}
	observer := thread.create_and_start_with_data(&telemetry, telemetry_consume)
	defer thread.destroy(observer)

	fmt.println("Press Enter to exit")
	input: [1]byte
	_, _ = os.read(os.stdin, input[:])

	audio_destroy(&unit)
	intrinsics.atomic_store_explicit(&telemetry.stop, true, .Release)
	thread.join(observer)
}
