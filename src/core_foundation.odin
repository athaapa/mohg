package mohg

foreign import CoreFoundation "system:CoreFoundation.framework"

CFAllocatorRef :: rawptr
CFTypeRef :: rawptr
CFStringRef :: rawptr
CFStringEncoding :: u32

kCFStringEncodingUTF8 :: CFStringEncoding(0x08000100)

foreign CoreFoundation {
	CFStringCreateWithCString :: proc(allocator: CFAllocatorRef, text: cstring, encoding: CFStringEncoding) -> CFStringRef ---

	CFRelease :: proc(value: CFTypeRef) ---
}
