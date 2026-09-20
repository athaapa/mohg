package mohg

import "base:intrinsics"

Spsc_Queue :: struct($T: typeid, $N: uint) where N > 0 && (N & (N - 1) == 0) {
	buffer: [N]T,
	head:   u64,
	tail:   u64,
}

spsc_try_push :: #force_inline proc "contextless" (q: ^$Q/Spsc_Queue($T, $N), item: T) -> bool {
	tail := intrinsics.atomic_load_explicit(&q.tail, .Relaxed)
	head := intrinsics.atomic_load_explicit(&q.head, .Acquire)
	if tail - head == u64(N) {
		return false
	}
	q.buffer[tail & u64(N - 1)] = item
	intrinsics.atomic_store_explicit(&q.tail, tail + 1, .Release)
	return true
}


spsc_try_pop :: #force_inline proc "contextless" (queue: ^$Q/Spsc_Queue($T, $N)) -> (T, bool) {
	head := intrinsics.atomic_load_explicit(&queue.head, .Relaxed)
	tail := intrinsics.atomic_load_explicit(&queue.tail, .Acquire)

	if head == tail {
		return T{}, false
	}

	item := queue.buffer[head & u64(N - 1)]
	intrinsics.atomic_store_explicit(&queue.head, head + 1, .Release)
	return item, true
}
