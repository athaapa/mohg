package bench

import "core:fmt"

// Reuse exactly the render benchmark's setup, warmup, and measurement path.
// No fitting or cycle estimation: these runs are intended for profiling.
scaling_run :: proc(opts: Options, phase: cstring) {
	fmt.printfln("Running n=%v k=%v L=%v ...", opts.voices, opts.unison, opts.oversampling)
	timing := render_benchmark(opts, opts.voices, phase)
	fmt.printfln(
		"  mean %.2f us/block, p50 %.2f us, p99 %.2f us",
		timing.mean_us,
		timing.p50_us,
		timing.p99_us,
	)
}

run_scaling :: proc(opts: Options) {
	fmt.printfln(
		"Render scaling: F=%v, B=%v, warmup=%v; elapsed timings",
		opts.frames,
		opts.blocks,
		opts.warmup,
	)
	fmt.printfln(
		"Filter: %.1f Hz cutoff, %.3f resonance, %.3f drive",
		opts.cutoff,
		opts.resonance,
		opts.drive,
	)

	fmt.println("\nUnison sweep (fixed voices and oversampling)")
	unison_counts := []int{2, 4, 8, 16}
	for k in unison_counts {
		run := opts
		run.unison = k
		scaling_run(run, "unison")
	}

	fmt.println("\nVoice sweep (fixed unison and oversampling)")
	voice_counts := []int{8, 16, 32}
	for n in voice_counts {
		run := opts
		run.voices = n
		scaling_run(run, "voices")
	}

	// At fixed L, the zero-voice cost combines L*c + d. A second L
	// provides the additional observation needed to separate those terms.
	fmt.println("\nZero-voice baselines (two oversampling factors)")
	other_factor := opts.oversampling == 1 ? 2 : 1
	factors := []int{other_factor, opts.oversampling}
	for factor in factors {
		run := opts
		run.voices = 0
		run.blocks = opts.baseline_blocks
		run.oversampling = factor
		scaling_run(run, "baseline")
	}
}
