package mohg

RNG :: struct {
	state: u32,
}

random_u32 :: proc "contextless" (rng: ^RNG) -> u32 {
	x := rng.state
	x ~= x << 13
	x ~= x >> 17
	x ~= x << 5

	rng.state = x
	return x
}

random_f64 :: proc "contextless" (rng: ^RNG) -> f64 {
	return f64(random_u32(rng)) / f64(1 << 32)
}

random_bipolar :: proc "contextless" (rng: ^RNG) -> f64 {
	return 2.0 * random_f64(rng) - 1.0
}
