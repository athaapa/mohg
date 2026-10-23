package mohg

import "base:intrinsics"
import "core:fmt"
import "core:time"

TELEMETRY_ENABLED :: #config(MOHG_TELEMETRY, false)
TELEMETRY_CAPACITY :: 256

Telemetry_Kind :: enum {
	NOTE_ON,
	RELEASE_STARTED,
	VOICE_REMOVED,
}

// Frame is an absolute output-frame index. For release/removal events, amplitude
// is after the envelope update; filter output is the final oversampled step of
// that frame, before envelope gain, mixing, decimation, chorus, and master gain.
// NOTE_ON has no filter sample yet.
Telemetry_Record :: struct {
	kind:      Telemetry_Kind,
	frame:     u64,
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
	when !TELEMETRY_ENABLED {return}
	if sink == nil {return}
	if !spsc_try_push(&sink.queue, record) {
		dropped := intrinsics.atomic_load_explicit(&sink.dropped, .Relaxed)
		intrinsics.atomic_store_explicit(&sink.dropped, dropped + 1, .Relaxed)
	}
}

telemetry_emit_voice :: proc "contextless" (
	sink: ^Telemetry, kind: Telemetry_Kind, frame: u64, voice: ^Voice,
) {
	when !TELEMETRY_ENABLED {return}
	if sink == nil {return}
	telemetry_emit(sink, Telemetry_Record{
		kind = kind, frame = frame, voice_id = voice.telemetry_id,
		note = voice.note, amplitude = voice.current_amplitude,
		left = voice.telemetry_filter_output[0], right = voice.telemetry_filter_output[1],
	})
}

// Bound each drain so even a continuously busy producer cannot monopolize it.
telemetry_drain :: proc(sink: ^Telemetry) {
	when !TELEMETRY_ENABLED {return}
	for _ in 0 ..< TELEMETRY_CAPACITY {
		r, ok := spsc_try_pop(&sink.queue)
		if !ok {break}
		if r.kind == .NOTE_ON {
			fmt.printf("[audio] %v frame=%d voice=%d note=%d stolen=%v amp=%.6f\n",
				r.kind, r.frame, r.voice_id, r.note, r.stolen, r.amplitude)
			continue
		}
		fmt.printf(
			"[audio] %v frame=%d voice=%d note=%d stolen=%v amp=%.6f filter=(%.9f, %.9f)\n",
			r.kind,
			r.frame,
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
	when !TELEMETRY_ENABLED {return}
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
