package mohg

import "base:intrinsics"

MIDI_QUEUE_CAPACITY :: 64
MIDI_QUEUE_MASK :: u64(MIDI_QUEUE_CAPACITY - 1)

Midi_Event_Kind :: enum u8 {
	Note_On,
	Note_Off,
}

Midi_Event :: struct {
	kind:     Midi_Event_Kind,
	channel:  u8,
	note:     u8,
	velocity: u8,
}

Midi_Event_Queue :: struct {
	buffer: [MIDI_QUEUE_CAPACITY]Midi_Event,
	head:   u64,
	tail:   u64,
}

midi_queue_try_push :: #force_inline proc "contextless" (
	queue: ^Midi_Event_Queue,
	event: Midi_Event,
) -> bool {
	tail := intrinsics.atomic_load_explicit(&queue.tail, .Relaxed)
	head := intrinsics.atomic_load_explicit(&queue.head, .Acquire)

	if tail - head == MIDI_QUEUE_CAPACITY {
		return false
	}

	index := int(tail & MIDI_QUEUE_MASK)
	queue.buffer[index] = event

	intrinsics.atomic_store_explicit(&queue.tail, tail + 1, .Release)
	return true
}

midi_queue_try_pop :: #force_inline proc "contextless" (
	queue: ^Midi_Event_Queue,
) -> (
	Midi_Event,
	bool,
) {
	head := intrinsics.atomic_load_explicit(&queue.head, .Relaxed)
	tail := intrinsics.atomic_load_explicit(&queue.tail, .Acquire)

	if head == tail {
		return Midi_Event{}, false
	}

	index := int(head & MIDI_QUEUE_MASK)
	event := queue.buffer[index]

	intrinsics.atomic_store_explicit(&queue.head, head + 1, .Release)
	return event, true
}
