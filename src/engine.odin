package mohg

// Engine: ties the synth to the platform. Owns everything the CoreAudio
// render callback touches and the queues that other threads feed.

Engine :: struct {
	synth:                 Synth,
	midi_event_queue:      ^Spsc_Queue(Midi_Event, MIDI_QUEUE_CAPACITY),
	parameter_event_queue: ^Spsc_Queue(Parameter_Event, PARAMETER_QUEUE_CAPACITY),
	log_queue:             ^Log_Queue,
	render_metrics:        Render_Metrics,
}

render :: proc "c" (
	inRefCon: rawptr,
	ioActionFlags: ^AudioUnitRenderActionFlags,
	inTimeStamp: ^AudioTimeStamp,
	inBusNumber: u32,
	inNumberFrames: u32,
	ioData: ^AudioBufferList,
) -> OSStatus {
	engine := cast(^Engine)inRefCon
	start := mach_absolute_time()

	synth := &engine.synth

	buffer := &ioData.mBuffers[0]
	samples := cast([^]f32)buffer.mData
	channel_count := int(buffer.mNumberChannels)

	synth_process_midi(synth, engine.midi_event_queue)
	process_parameter_events(synth, engine.parameter_event_queue)

	synth_render(synth, synth.voices, samples, int(inNumberFrames), channel_count)

	elapsed := mach_absolute_time() - start
	render_metrics_record(&engine.render_metrics, elapsed, inNumberFrames)

	return 0
}
