package bench

foreign import signpost_bridge "../build/signpost_bridge.o"

foreign signpost_bridge {
	mohg_bench_signpost_log :: proc() -> rawptr ---
	mohg_bench_signpost_begin :: proc(log: rawptr, phase: cstring, n, k, l, f, b: i32) -> u64 ---
	mohg_bench_signpost_end :: proc(log: rawptr, id: u64) ---
}
