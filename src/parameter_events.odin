package mohg

// Parameter event transport: control-thread changes (cutoff, resonance)
// crossing to the audio thread, applied to the synth between renders.

PARAMETER_QUEUE_CAPACITY :: 512

Ladder_Filter_Cutoff_Event :: struct {
	cutoff_hz: f64,
}
Ladder_Filter_Resonance_Event :: struct {
	resonance: f64,
}

Ladder_Filter_Drive_Event :: struct {
	drive: f64,
}

Parameter_Event :: union {
	Ladder_Filter_Cutoff_Event,
	Ladder_Filter_Resonance_Event,
	Ladder_Filter_Drive_Event,
}

process_parameter_events :: proc "contextless" (
	synth: ^Synth,
	queue: ^Spsc_Queue(Parameter_Event, PARAMETER_QUEUE_CAPACITY),
) {
	event, ok := spsc_try_pop(queue)
	if ok {
		switch e in event {
		case Ladder_Filter_Cutoff_Event:
			ladder_filter_set_parameters(
				&synth.ladder_filter,
				e.cutoff_hz,
				synth.ladder_filter.resonance,
				synth.ladder_filter.drive,
			)

		case Ladder_Filter_Resonance_Event:
			ladder_filter_set_parameters(
				&synth.ladder_filter,
				synth.ladder_filter.cutoff_hz,
				e.resonance,
				synth.ladder_filter.drive,
			)
		case Ladder_Filter_Drive_Event:
			ladder_filter_set_parameters(
				&synth.ladder_filter,
				synth.ladder_filter.cutoff_hz,
				synth.ladder_filter.resonance,
				e.drive,
			)
		}

		for i in 0 ..< synth.voices.voice_count {
			ladder_filter_set_parameters(
				&synth.voices.voices[i].left_ladder_filter,
				synth.ladder_filter.cutoff_hz,
				synth.ladder_filter.resonance,
				synth.ladder_filter.drive,
			)
			ladder_filter_set_parameters(
				&synth.voices.voices[i].right_ladder_filter,
				synth.ladder_filter.cutoff_hz,
				synth.ladder_filter.resonance,
				synth.ladder_filter.drive,
			)

		}
	}
}
