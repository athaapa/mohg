package mohg

poly_blep :: proc "contextless" (phase: f64, step: f64) -> f64 {
	t := phase
	dt := step
	if t < dt {
		t /= dt
		return t + t - t * t - 1.0
	} else if t > 1.0 - dt {
		t = (t - 1.0) / dt
		return t * t + t + t + 1.0
	}
	return 0.0
}

poly_blamp :: proc "contextless" (phase: f64, step: f64) -> f64 {
	y := 0.0
	t := phase
	dt := step
	if t >= 0.0 && t < 2.0 * step {
		u := 2.0 - (t / dt)
		u2 := u * u
		y -= u2 * u2 * u

		if t < dt {
			v := 1.0 - (t / dt)
			v2 := v * v
			y += 4.0 * (v2 * v2 * v)
		}
	}

	return y * dt / 15.0
}
