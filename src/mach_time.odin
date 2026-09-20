package mohg

foreign import System "system:System"

Kern_Return :: i32

Mach_Timebase_Info :: struct {
	numer: u32,
	denom: u32,
}

foreign System {
	mach_absolute_time :: proc() -> u64 ---

	mach_timebase_info :: proc(info: ^Mach_Timebase_Info) -> Kern_Return ---
}
