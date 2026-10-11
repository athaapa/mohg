package bench

import mohg "../src"
import "core:fmt"
import "core:slice"

Render_Timing :: struct {
	mean_us, p50_us, p99_us: f64,
}

// Setup, warmup, and reporting are outside the timed region. This measures
// back-to-back synth_render calls, not live audio scheduling or MIDI handling.
render_benchmark :: proc(opts: Options, voice_count: int) -> Render_Timing {
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
		max_voices = u8(voice_count),
		unison_count = u8(opts.unison),
		detune_cents = 15,
		rng = mohg.RNG{state = 1}, // Repeatable phases, with a nonzero RNG seed.
	}
	mohg.ladder_filter_set_sample_rate(&synth.ladder_filter, SAMPLE_RATE)
	mohg.ladder_filter_set_parameters(
		&synth.ladder_filter,
		f32(opts.cutoff),
		f32(opts.resonance),
		f32(opts.drive),
	)
	midi_queue := mohg.Spsc_Queue(mohg.Midi_Event, mohg.MIDI_QUEUE_CAPACITY){}
	parameter_queue := mohg.Spsc_Queue(mohg.Parameter_Event, mohg.PARAMETER_QUEUE_CAPACITY){}
	for i in 0 ..< voice_count {
		// Repeat a valid MIDI note range for pools larger than 80 voices.
		if !mohg.spsc_try_push(
			&midi_queue,
			mohg.Midi_Note_On{note = u8(48 + i % 80), velocity = 100},
		) {
			panic("MIDI queue filled during benchmark setup")
		}
	}
	mohg.synth_process_midi(&synth, &midi_queue, &parameter_queue)
	assert(int(voices.voice_count) == voice_count)
	samples := make([]f32, opts.frames * CHANNEL_COUNT)
	defer delete(samples)
	durations := make([]u64, opts.blocks)
	defer delete(durations)
	for _ in 0 ..< opts.warmup {
		mohg.synth_render(&synth, &voices, raw_data(samples), opts.frames, CHANNEL_COUNT)
	}
	timebase: mohg.Mach_Timebase_Info
	if mohg.mach_timebase_info(&timebase) != 0 {panic("mach_timebase_info failed")}
	for i in 0 ..< opts.blocks {
		start := mohg.mach_absolute_time()
		mohg.synth_render(&synth, &voices, raw_data(samples), opts.frames, CHANNEL_COUNT)
		durations[i] = mohg.mach_absolute_time() - start
	}
	// Summation and sorting happen after measurement. Percentiles use nearest
	// rank: ceil(p * N) - 1, including when only one block is requested.
	total_ticks: u64
	for ticks in durations {total_ticks += ticks}
	slice.sort(durations)
	ticks_to_us := f64(timebase.numer) / f64(timebase.denom) / 1000
	p50_index := (opts.blocks * 50 + 99) / 100 - 1
	p99_index := (opts.blocks * 99 + 99) / 100 - 1
	return Render_Timing {
		mean_us = f64(total_ticks) / f64(opts.blocks) * ticks_to_us,
		p50_us = f64(durations[p50_index]) * ticks_to_us,
		p99_us = f64(durations[p99_index]) * ticks_to_us,
	}
}

run_render :: proc(opts: Options) {
	fmt.printfln(
		"Offline render: %v Hz, %v unison, %v frames, %v warmup blocks, %v measured blocks",
		SAMPLE_RATE,
		opts.unison,
		opts.frames,
		opts.warmup,
		opts.blocks,
	)
	fmt.printfln(
		"Filter: %.1f Hz cutoff, %.3f resonance, %.3f drive",
		opts.cutoff,
		opts.resonance,
		opts.drive,
	)
	deadline_us := f64(opts.frames) / SAMPLE_RATE * 1e6
	fmt.printfln(
		"Buffer budget: %.2f us (reported utilization is the mean, not worst case)",
		deadline_us,
	)
	fmt.println("\nBlock timings in us; mean/frame is us per frame.")
	fmt.printfln("%6s %12s %12s %12s %12s %10s",
		"Voices", "Mean/block", "p50/block", "p99/block", "Mean/frame", "Budget %")
	fmt.println("------ ------------ ------------ ------------ ------------ ----------")
	counts := []int{opts.voices}
	if opts.sweep {counts = []int{16, 32, 64, 128}}
	for count in counts {
		timing := render_benchmark(opts, count)
		fmt.printfln(
			"%6s %12s %12s %12s %12s %10s",
			fmt.tprint(count),
			fmt.tprintf("%.2f", timing.mean_us),
			fmt.tprintf("%.2f", timing.p50_us),
			fmt.tprintf("%.2f", timing.p99_us),
			fmt.tprintf("%.2f", timing.mean_us / f64(opts.frames)),
			fmt.tprintf("%.2f", timing.mean_us / deadline_us * 100),
		)
	}
}
