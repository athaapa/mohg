package mohg

// Parameter event transport: control-thread changes (cutoff, resonance)
// crossing to the audio thread, applied to the synth between renders.

PARAMETER_QUEUE_CAPACITY :: 512

Ladder_Filter_Cutoff_Event :: struct {
	cutoff_hz: f32,
}
Ladder_Filter_Resonance_Event :: struct {
	resonance: f32,
}

Parameter_Event :: union {
	Ladder_Filter_Cutoff_Event,
	Ladder_Filter_Resonance_Event,
}

// TODO: Update all active voices with these parameters
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
			)

		case Ladder_Filter_Resonance_Event:
			ladder_filter_set_parameters(
				&synth.ladder_filter,
				synth.ladder_filter.cutoff_hz,
				e.resonance,
			)
		}
	}
}
