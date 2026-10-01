package bench

import mohg "../src"
import "core:fmt"

VOICE_COUNT :: 32
FRAME_COUNT :: 64
CHANNEL_COUNT :: 2
WARMUP_BLOCKS :: 100
MEASURED_BLOCKS :: 1_000
SAMPLE_RATE :: 48_000.0
UNISON_COUNT :: 16

main :: proc() {
	voices := mohg.Voices{}
	synth := mohg.Synth {
		sample_rate = SAMPLE_RATE,
		adsr_config = mohg.ADSR_Config {
			attack_seconds = 0.025,
			decay_seconds = 0.25,
			sustain_level = 1,
			release_seconds = 0.1,
		},
		voices = &voices,
		max_voices = VOICE_COUNT,
		unison_count = UNISON_COUNT,
		detune_cents = 15,
	}
	mohg.ladder_filter_set_sample_rate(&synth.ladder_filter, f32(SAMPLE_RATE))
	mohg.ladder_filter_set_parameters(&synth.ladder_filter, 7_000, 0.6)

	midi_queue := mohg.Spsc_Queue(mohg.Midi_Event, mohg.MIDI_QUEUE_CAPACITY){}
	parameter_queue := mohg.Spsc_Queue(mohg.Parameter_Event, mohg.PARAMETER_QUEUE_CAPACITY){}
	for i in 0 ..< VOICE_COUNT {
		if !mohg.spsc_try_push(&midi_queue, mohg.Midi_Note_On{note = u8(48 + i), velocity = 100}) {
			panic("MIDI queue filled during benchmark setup")
		}
	}
	mohg.synth_process_midi(&synth, &midi_queue, &parameter_queue)
	assert(voices.voice_count == VOICE_COUNT)

	samples: [FRAME_COUNT * CHANNEL_COUNT]f32
	for _ in 0 ..< WARMUP_BLOCKS {
		mohg.synth_render(&synth, &voices, raw_data(samples[:]), FRAME_COUNT, CHANNEL_COUNT)
	}

	timebase: mohg.Mach_Timebase_Info
	if mohg.mach_timebase_info(&timebase) != 0 {
		panic("mach_timebase_info failed")
	}
	metrics := mohg.Render_Metrics{}
	mohg.render_metrics_init(&metrics, timebase, SAMPLE_RATE)
	metrics.bucket_width_ticks = max(mohg.nanoseconds_to_ticks(10_000, timebase), u64(1))

	for _ in 0 ..< MEASURED_BLOCKS {
		start := mohg.mach_absolute_time()
		mohg.synth_render(&synth, &voices, raw_data(samples[:]), FRAME_COUNT, CHANNEL_COUNT)
		elapsed := mohg.mach_absolute_time() - start
		mohg.render_metrics_record(&metrics, elapsed, FRAME_COUNT)
	}

	fmt.printfln(
		"offline render: %v voices, %v unison oscillators, %v frames, %.0f Hz",
		VOICE_COUNT,
		synth.unison_count,
		FRAME_COUNT,
		SAMPLE_RATE,
	)
	mohg.render_metrics_print(&metrics)
	fmt.printfln("  last output sample: %.6f", samples[len(samples) - 1])
}
