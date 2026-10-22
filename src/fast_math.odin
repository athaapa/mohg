package mohg

import "core:math"
fast_tanh :: proc "contextless" (x: f64) -> f64 {
	x := math.clamp(x, -3, 3)
	x2 := x * x
	return x * (27 + x2) / (27 + 9 * x2)
}
