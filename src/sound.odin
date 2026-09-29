package mohg

import "core:math"

cents_to_freq_multiplier :: proc "contextless" (cents: f64) -> f64 {
	return math.pow(2.0, cents / 1200)
}
