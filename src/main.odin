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
	when TELEMETRY_ENABLED {telemetry := Telemetry{}}

	synth := Synth {
		sample_rate = 48_000,
		volume = 1,
		volume_target = 1,
		adsr_config = ADSR_Config {
			attack_seconds = 0.15,
			decay_seconds = 0.25,
			sustain_level = 1,
			release_seconds = 0.15,
		},
		ladder_filter = Ladder_Filter{},
		voices = &voices,
		max_voices = 4,
		unison_count = 3,
		detune_cents = 15,
		rng = RNG{state = 1},
		waveform = Waveform.SAW,
		oversampling_factor = 1,
		left_decimator = Decimator{},
		right_decimator = Decimator{},
		analog = Analog_Config {
			voice_tune_spread_cents = 2.5,
			voice_cutoff_spread = 0.05,
			voice_resonance_spread = 0.02,
			osc_tune_spread_cents = 1,
			drift_rms_cents = 1.5,
			drift_rate_hz = 0.5,
		},
		chorus = Chorus{},
	}

	when TELEMETRY_ENABLED {synth.telemetry = &telemetry}
	synth_update_drift_coefficients(&synth)

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
	defer {
		cleanup_status := midi_input_destroy(&midi)
		if cleanup_status != 0 {fmt.printfln("failed to dispose MIDI client: %v", cleanup_status)}
	}

	unit: AudioUnit
	audio_init(&engine, &unit)

	ladder_filter_set_sample_rate(
		&engine.synth.ladder_filter,
		engine.synth.sample_rate * f64(engine.synth.oversampling_factor),
	)
	ladder_filter_set_parameters(&engine.synth.ladder_filter, 10_000, 0, 2)

	decimator_init(
		&engine.synth.left_decimator,
		synth.oversampling_factor,
		engine.synth.sample_rate,
	)
	decimator_init(
		&engine.synth.right_decimator,
		synth.oversampling_factor,
		engine.synth.sample_rate,
	)

	chorus_init(&engine.synth.chorus, engine.synth.sample_rate)

	// start
	status = AudioOutputUnitStart(unit)
	if (status != 0) {
		panic("failed to start audio unit")
	}
	when TELEMETRY_ENABLED {
		observer := thread.create_and_start_with_data(&telemetry, telemetry_consume)
		defer thread.destroy(observer)
	}

	fmt.println("Press Enter to exit")
	input: [1]byte
	_, _ = os.read(os.stdin, input[:])

	audio_destroy(&unit)
	when TELEMETRY_ENABLED {
		intrinsics.atomic_store_explicit(&telemetry.stop, true, .Release)
		thread.join(observer)
	}
}
