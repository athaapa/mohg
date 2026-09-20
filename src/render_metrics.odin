package mohg

import "core:fmt"
import "core:math"

RENDER_BUCKET_COUNT    :: 512
RENDER_BUCKET_WIDTH_NS :: u64(10_000)

Render_Metrics :: struct {
	buckets:            [RENDER_BUCKET_COUNT]u64,
	bucket_width_ticks: u64,
	ticks_per_frame:    f64,
	callback_count:     u64,
	total_ticks:        u64,
	max_ticks:          u64,
	deadline_misses:    u64,
	min_deadline_ticks: u64,
	timebase_numer:     u32,
	timebase_denom:     u32,
}

nanoseconds_to_ticks :: proc "contextless" (
	nanoseconds: u64,
	timebase: Mach_Timebase_Info,
) -> u64 {
	numer := u64(timebase.numer)
	denom := u64(timebase.denom)
	return (nanoseconds * denom + numer - 1) / numer
}

ticks_to_microseconds :: proc "contextless" (
	ticks: u64,
	metrics: ^Render_Metrics,
) -> f64 {
	return f64(ticks) * f64(metrics.timebase_numer) /
		f64(metrics.timebase_denom) / 1_000.0
}

render_metrics_init :: proc(
	metrics: ^Render_Metrics,
	timebase: Mach_Timebase_Info,
	sample_rate: f64,
) {
	metrics^ = Render_Metrics{}
	metrics.timebase_numer = timebase.numer
	metrics.timebase_denom = timebase.denom
	metrics.bucket_width_ticks = math.max(
		nanoseconds_to_ticks(RENDER_BUCKET_WIDTH_NS, timebase),
		u64(1),
	)

	ticks_per_second := 1_000_000_000.0 * f64(timebase.denom) / f64(timebase.numer)
	metrics.ticks_per_frame = ticks_per_second / sample_rate
}

render_metrics_record :: #force_inline proc "contextless" (
	metrics: ^Render_Metrics,
	elapsed_ticks: u64,
	frame_count: u32,
) {
	bucket := elapsed_ticks / metrics.bucket_width_ticks
	if bucket >= RENDER_BUCKET_COUNT - 1 {
		bucket = RENDER_BUCKET_COUNT - 1
	}
	metrics.buckets[int(bucket)] += 1

	metrics.callback_count += 1
	metrics.total_ticks += elapsed_ticks
	metrics.max_ticks = max(metrics.max_ticks, elapsed_ticks)

	deadline_ticks := u64(f64(frame_count) * metrics.ticks_per_frame)
	if metrics.min_deadline_ticks == 0 || deadline_ticks < metrics.min_deadline_ticks {
		metrics.min_deadline_ticks = deadline_ticks
	}
	if elapsed_ticks > deadline_ticks {
		metrics.deadline_misses += 1
	}
}

render_metrics_quantile_bucket :: proc(
	metrics: ^Render_Metrics,
	percentile: u64,
) -> int {
	if metrics.callback_count == 0 {
		return 0
	}

	target := (metrics.callback_count * percentile + 99) / 100
	cumulative: u64
	for count, bucket in metrics.buckets {
		cumulative += count
		if cumulative >= target {
			return bucket
		}
	}

	return RENDER_BUCKET_COUNT - 1
}

render_metrics_print_quantile :: proc(
	label: string,
	metrics: ^Render_Metrics,
	percentile: u64,
) {
	bucket := render_metrics_quantile_bucket(metrics, percentile)
	if bucket == RENDER_BUCKET_COUNT - 1 {
		lower_bound_ticks := u64(bucket) * metrics.bucket_width_ticks
		fmt.printfln("%s: >= %.3f us (overflow bucket)", label, ticks_to_microseconds(lower_bound_ticks, metrics))
		return
	}

	upper_bound_ticks := u64(bucket + 1) * metrics.bucket_width_ticks
	fmt.printfln("%s: <= %.3f us", label, ticks_to_microseconds(upper_bound_ticks, metrics))
}

render_metrics_print :: proc(metrics: ^Render_Metrics) {
	fmt.println("render metrics")
	fmt.printfln("  callbacks: %v", metrics.callback_count)
	if metrics.callback_count == 0 {
		return
	}

	render_metrics_print_quantile("  p50", metrics, 50)
	render_metrics_print_quantile("  p99", metrics, 99)

	mean_ticks := metrics.total_ticks / metrics.callback_count
	fmt.printfln("  mean: %.3f us", ticks_to_microseconds(mean_ticks, metrics))
	fmt.printfln("  max: %.3f us", ticks_to_microseconds(metrics.max_ticks, metrics))
	fmt.printfln("  deadline: %.3f us (minimum observed)", ticks_to_microseconds(metrics.min_deadline_ticks, metrics))
	fmt.printfln("  deadline misses: %v", metrics.deadline_misses)

	if metrics.min_deadline_ticks > 0 {
		utilization := 100.0 * f64(metrics.max_ticks) / f64(metrics.min_deadline_ticks)
		fmt.printfln("  maximum deadline utilization: %.2f%%", utilization)
	}
}
