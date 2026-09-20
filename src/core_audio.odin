package mohg

foreign import AudioToolbox "system:AudioToolbox.framework"

OSType :: u32
OSStatus :: i32
AudioComponent :: rawptr
AudioComponentInstance :: rawptr
AudioUnit :: AudioComponentInstance
AudioFormatID :: u32
AudioFormatFlags :: u32
AudioUnitPropertyID :: u32
AudioUnitScope :: u32
AudioUnitElement :: u32

AudioComponentDescription :: struct {
	componentType:         OSType,
	componentSubType:      OSType,
	componentManufacturer: OSType,
	componentFlags:        u32,
	componentFlagsMask:    u32,
}

AudioStreamBasicDescription :: struct {
	mSampleRate:       f64,
	mFormatID:         AudioFormatID,
	mFormatFlags:      AudioFormatFlags,
	mBytesPerPacket:   u32,
	mFramesPerPacket:  u32,
	mBytesPerFrame:    u32,
	mChannelsPerFrame: u32,
	mBitsPerChannel:   u32,
	mReserved:         u32,
}

SMPTETimeType :: enum u32 {
	kSMPTETimeType24       = 0,
	kSMPTETimeType25       = 1,
	kSMPTETimeType30Drop   = 2,
	kSMPTETimeType30       = 3,
	kSMPTETimeType2997     = 4,
	kSMPTETimeType2997Drop = 5,
	kSMPTETimeType60       = 6,
	kSMPTETimeType5994     = 7,
	kSMPTETimeType60Drop   = 8,
	kSMPTETimeType5994Drop = 9,
	kSMPTETimeType50       = 10,
	kSMPTETimeType2398     = 11,
}

SMPTETimeFlags :: enum u32 {
	kSMPTETimeUnknown = 0,
	kSMPTETimeValid   = (u32(1) << 0),
	kSMPTETimeRunning = (u32(1) << 1),
}

SMPTETime :: struct {
	mSubframes:       i16,
	mSubframeDivisor: i16,
	mCounter:         u32,
	mType:            SMPTETimeType,
	mFlags:           SMPTETimeFlags,
	mHours:           i16,
	mMinutes:         i16,
	mSeconds:         i16,
	mFrames:          i16,
}

AudioTimeStampFlags :: enum u32 {
	kAudioTimeStampNothingValid        = 0,
	kAudioTimeStampSampleTimeValid     = (u32(1) << 0),
	kAudioTimeStampHostTimeValid       = (u32(1) << 1),
	kAudioTimeStampRateScalarValid     = (u32(1) << 2),
	kAudioTimeStampWordClockTimeValid  = (u32(1) << 3),
	kAudioTimeStampSMPTETimeValid      = (u32(1) << 4),
	kAudioTimeStampSampleHostTimeValid = (kAudioTimeStampSampleTimeValid |
		kAudioTimeStampHostTimeValid),
}

AudioTimeStamp :: struct {
	mSampleTime:    f64,
	mHostTime:      u64,
	mRateScalar:    f64,
	mWordClockTime: u64,
	mSMPTETime:     SMPTETime,
	mFlags:         AudioTimeStampFlags,
	mReserved:      u32,
}

AudioUnitRenderActionFlags :: u32

kAudioUnitRenderAction_PreRender :: AudioUnitRenderActionFlags(1 << 2)
kAudioUnitRenderAction_PostRender :: AudioUnitRenderActionFlags(1 << 3)
kAudioUnitRenderAction_OutputIsSilence :: AudioUnitRenderActionFlags(1 << 4)
kAudioOfflineUnitRenderAction_Preflight :: AudioUnitRenderActionFlags(1 << 5)
kAudioOfflineUnitRenderAction_Render :: AudioUnitRenderActionFlags(1 << 6)
kAudioOfflineUnitRenderAction_Complete :: AudioUnitRenderActionFlags(1 << 7)
kAudioUnitRenderAction_PostRenderError :: AudioUnitRenderActionFlags(1 << 8)
kAudioUnitRenderAction_DoNotCheckRenderArgs :: AudioUnitRenderActionFlags(1 << 9)

AudioBuffer :: struct {
	mNumberChannels: u32,
	mDataByteSize:   u32,
	mData:           rawptr,
}

AudioBufferList :: struct {
	mNumberBuffers: u32,
	mBuffers:       [1]AudioBuffer, // this is a variable length array of mNumberBuffers elements
}

AURenderCallback :: proc "c" (
	inRefCon: rawptr,
	ioActionFlags: ^AudioUnitRenderActionFlags,
	inTimeStamp: ^AudioTimeStamp,
	inBusNumber: u32,
	inNumberFrames: u32,
	ioData: ^AudioBufferList,
) -> OSStatus

AURenderCallbackStruct :: struct {
	inputProc:       AURenderCallback,
	inputProcRefCon: rawptr,
}

foreign AudioToolbox {
	AudioComponentFindNext :: proc(inComponent: AudioComponent, inDesc: ^AudioComponentDescription) -> AudioComponent ---
	AudioComponentInstanceNew :: proc(inComponent: AudioComponent, outInstance: ^AudioComponentInstance) -> OSStatus ---
	AudioUnitSetProperty :: proc(inUnit: AudioUnit, inID: AudioUnitPropertyID, inScope: AudioUnitScope, inElement: AudioUnitElement, inData: rawptr, inDataSize: u32) -> OSStatus ---
	AudioUnitInitialize :: proc(inUnit: AudioUnit) -> OSStatus ---
	AudioOutputUnitStart :: proc(ci: AudioUnit) -> OSStatus ---
	AudioOutputUnitStop :: proc(ci: AudioUnit) -> OSStatus ---
	AudioUnitUninitialize :: proc(inUnit: AudioUnit) -> OSStatus ---
	AudioComponentInstanceDispose :: proc(inInstance: AudioComponentInstance) -> OSStatus ---
	AudioUnitGetProperty :: proc(inUnit: AudioUnit, inID: AudioUnitPropertyID, inScope: AudioUnitScope, inElement: AudioUnitElement, outData: rawptr, ioDataSize: ^u32) -> OSStatus ---
}


kAudioUnitType_Output :: OSType((u32('a') << 24) | (u32('u') << 16) | (u32('o') << 8) | u32('u'))

kAudioUnitSubType_DefaultOutput :: OSType(
	(u32('d') << 24) | (u32('e') << 16) | (u32('f') << 8) | u32(' '),
)

kAudioUnitManufacturer_Apple :: OSType(
	(u32('a') << 24) | (u32('p') << 16) | (u32('p') << 8) | u32('l'),
)

kAudioUnitProperty_StreamFormat :: AudioUnitPropertyID(8)
kAudioUnitProperty_SetRenderCallback :: AudioUnitPropertyID(23)
kAudioUnitScope_Input :: AudioUnitScope(1)

kAudioFormatLinearPCM :: AudioFormatID(
	(u32('l') << 24) | (u32('p') << 16) | (u32('c') << 8) | u32('m'),
)

kAudioFormatFlagIsFloat :: AudioFormatFlags(1 << 0)
kAudioFormatFlagIsPacked :: AudioFormatFlags(1 << 3)

kAudioUnitScope_Output :: AudioUnitScope(2)


audio_init :: proc(engine: ^Engine, unit: ^AudioUnit) {
	synth := &engine.synth
	// describe DefaultOutput
	desc := AudioComponentDescription {
		componentType         = kAudioUnitType_Output,
		componentSubType      = kAudioUnitSubType_DefaultOutput,
		componentManufacturer = kAudioUnitManufacturer_Apple,
		componentFlags        = 0,
		componentFlagsMask    = 0,
	}

	// find it
	component := AudioComponentFindNext(nil, &desc)

	// instantiate it
	status := AudioComponentInstanceNew(component, unit)
	if (status != 0) {
		panic("failed to create audio component")
	}

	device_format := AudioStreamBasicDescription{}
	format_size := u32(size_of(device_format))

	status = AudioUnitGetProperty(
		unit^,
		kAudioUnitProperty_StreamFormat,
		kAudioUnitScope_Output,
		0,
		rawptr(&device_format),
		&format_size,
	)

	if (status != 0) {
		panic("failed to get audio unit stream format")
	}

	synth.sample_rate = device_format.mSampleRate

	// set format
	channel_count := u32(2)
	bytes_per_sample := u32(size_of(f32))
	bytes_per_frame := channel_count * bytes_per_sample

	format := AudioStreamBasicDescription {
		mSampleRate       = synth.sample_rate,
		mFormatID         = kAudioFormatLinearPCM,
		mFormatFlags      = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
		mChannelsPerFrame = channel_count,
		mBytesPerPacket   = bytes_per_frame,
		mFramesPerPacket  = 1,
		mBytesPerFrame    = bytes_per_frame,
		mBitsPerChannel   = 32,
		mReserved         = 0,
	}

	status = AudioUnitSetProperty(
		unit^,
		kAudioUnitProperty_StreamFormat,
		kAudioUnitScope_Input,
		0,
		rawptr(&format),
		u32(size_of(format)),
	)

	if (status != 0) {
		panic("failed to set stream format")
	}

	// set up callback
	callback := AURenderCallbackStruct {
		inputProc       = render,
		inputProcRefCon = engine,
	}

	status = AudioUnitSetProperty(
		unit^,
		kAudioUnitProperty_SetRenderCallback,
		kAudioUnitScope_Input,
		0,
		rawptr(&callback),
		u32(size_of(callback)),
	)

	if (status != 0) {
		panic("failed to set render callback")
	}

	// initialize
	status = AudioUnitInitialize(unit^)
	if (status != 0) {
		panic("failed to initialize audio unit")
	}

}

audio_destroy :: proc(unit: ^AudioUnit) {
	// clean up
	status := AudioOutputUnitStop(unit^)
	if (status != 0) {
		panic("failed to stop audio unit")
	}

	status = AudioUnitUninitialize(unit^)
	if (status != 0) {
		panic("failed to uninitialize audio unit")
	}

	status = AudioComponentInstanceDispose(unit^)

	if (status != 0) {
		panic("failed to dispose audio unit")
	}
}
