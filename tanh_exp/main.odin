package tanh_exp

import "base:intrinsics"
import "core:fmt"
import "core:math"
import "core:time"

ITERATIONS :: 50000

fast_tanh :: proc(x: f64) -> f64 {
	x2 := x * x
	return x * (27 + x2) / (27 + 9 * x2)
}

bench_fast_tanh :: #force_no_inline proc(input: f64) -> u64 {
	input := input
	sink: f64

	// Baseline
	start := time.read_cycle_counter()

	for _ in 0 ..< ITERATIONS {
		x := intrinsics.volatile_load(&input)
		intrinsics.volatile_store(&sink, x)
	}

	baseline := time.read_cycle_counter() - start

	// Actual tanh benchmark
	start = time.read_cycle_counter()

	for _ in 0 ..< ITERATIONS {
		x := intrinsics.volatile_load(&input)
		result := fast_tanh(x)
		intrinsics.volatile_store(&sink, result)
	}

	total := time.read_cycle_counter() - start

	return total - baseline
}


bench_tanh :: #force_no_inline proc(input: f64) -> u64 {
	input := input
	sink: f64

	// Baseline
	start := time.read_cycle_counter()

	for _ in 0 ..< ITERATIONS {
		x := intrinsics.volatile_load(&input)
		intrinsics.volatile_store(&sink, x)
	}

	baseline := time.read_cycle_counter() - start

	// Actual tanh benchmark
	start = time.read_cycle_counter()

	for _ in 0 ..< ITERATIONS {
		x := intrinsics.volatile_load(&input)
		result := math.tanh(x)
		intrinsics.volatile_store(&sink, result)
	}

	total := time.read_cycle_counter() - start

	return total - baseline
}

bench_cycle_counter :: proc() -> u64 {
	sink: u64
	start := time.read_cycle_counter()

	for _ in 0 ..< ITERATIONS {
		value := time.read_cycle_counter()
		intrinsics.volatile_store(&sink, value)
	}

	duration := time.read_cycle_counter() - start

	return duration
}


main :: proc() {
	arr := [10]f64{0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0}
	freq := intrinsics.read_cycle_counter_frequency()

	fmt.printfln("iterations: %v", ITERATIONS)
	fmt.printfln("counter frequency: %v Hz", freq)

	cycle_counter_cycles := bench_cycle_counter()
	cycle_counter_ns_per_iteration := f64(cycle_counter_cycles) * 1e9 / f64(freq) / f64(ITERATIONS)

	fmt.printfln("read_cycle_counter ns/itr: %v\n", cycle_counter_ns_per_iteration)

	for input in arr {
		tanh_cycles := bench_tanh(input)
		tanh_ns_per_iteration := f64(tanh_cycles) * 1e9 / f64(freq) / f64(ITERATIONS)

		fast_tanh_cycles := bench_fast_tanh(input)
		fast_tanh_ns_per_iteration := f64(fast_tanh_cycles) * 1e9 / f64(freq) / f64(ITERATIONS)


		fmt.printfln("input: %v", input)
		fmt.printfln("tanh ns/itr: %v", tanh_ns_per_iteration)
		fmt.printfln("fast tanh ns/itr: %v\n", fast_tanh_ns_per_iteration)
	}

}
