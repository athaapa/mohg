package mohg

import "base:intrinsics"
import "core:fmt"
import "core:time"

TELEMETRY_CAPACITY :: 256

Telemetry_Kind :: enum {
	NOTE_ON,
	RELEASE_STARTED,
	VOICE_REMOVED,
}

// Positions refer to the output frame and the oversampled step within it.
// Filter outputs are the voice's contribution before mixing/decimation.
Telemetry_Record :: struct {
	kind:      Telemetry_Kind,
	frame:     u64,
	subframe:  u8,
	voice_id:  u64,
	note:      u8,
	stolen:    bool,
	amplitude: f64,
	left:      f64,
	right:     f64,
}

Telemetry :: struct {
	queue:   Spsc_Queue(Telemetry_Record, TELEMETRY_CAPACITY),
	dropped: u64, // Atomic: audio writes, consumer reads.
	stop:    bool, // Atomic: main writes, consumer reads.
}

// Sole producer: audio thread. A missing telemetry sink disables recording.
telemetry_emit :: proc "contextless" (sink: ^Telemetry, record: Telemetry_Record) {
	if sink == nil {return}
	if !spsc_try_push(&sink.queue, record) {
		dropped := intrinsics.atomic_load_explicit(&sink.dropped, .Relaxed)
		intrinsics.atomic_store_explicit(&sink.dropped, dropped + 1, .Relaxed)
	}
}

// Bound each drain so even a continuously busy producer cannot monopolize it.
telemetry_drain :: proc(sink: ^Telemetry) {
	for _ in 0 ..< TELEMETRY_CAPACITY {
		r, ok := spsc_try_pop(&sink.queue)
		if !ok {break}
		fmt.printf(
			"[audio] %v frame=%d sub=%d voice=%d note=%d stolen=%v amp=%.6f filter=(%.9f, %.9f)\n",
			r.kind,
			r.frame,
			r.subframe,
			r.voice_id,
			r.note,
			r.stolen,
			r.amplitude,
			r.left,
			r.right,
		)
	}
}

// Normal-priority observer.
telemetry_consume :: proc(data: rawptr) {
	sink := cast(^Telemetry)data
	last_dropped: u64
	for {
		stopping := intrinsics.atomic_load_explicit(&sink.stop, .Acquire)
		telemetry_drain(sink)
		dropped := intrinsics.atomic_load_explicit(&sink.dropped, .Relaxed)
		if dropped != last_dropped {
			fmt.printf("[audio] telemetry dropped=%d (+%d)\n", dropped, dropped - last_dropped)
			last_dropped = dropped
		}
		// Main stops audio before publishing stop, so this drain is final.
		if stopping {break}
		time.sleep(20 * time.Millisecond)
	}
}
