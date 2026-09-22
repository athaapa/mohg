package mohg

import "core:c"
import "core:fmt"
foreign import CoreMIDI "system:CoreMIDI.framework"
foreign import core_midi_bridge "../build/core_midi_bridge.o"

MIDIObjectRef :: u32
MIDIClientRef :: MIDIObjectRef
MIDIPortRef :: MIDIObjectRef
MIDITimeStamp :: u64
ItemCount :: c.ulong
MIDIEndpointRef :: MIDIObjectRef

MIDINotificationMessageID :: enum i32 {
	kMIDIMsgSetupChanged           = 1,
	kMIDIMsgObjectAdded            = 2,
	kMIDIMsgObjectRemoved          = 3,
	kMIDIMsgPropertyChanged        = 4,
	kMIDIMsgThruConnectionsChanged = 5,
	kMIDIMsgSerialPortOwnerChanged = 6,
	kMIDIMsgIOError                = 7,
}

MIDIProtocolID :: enum i32 {
	kMIDIProtocol_1_0 = 1,
	kMIDIProtocol_2_0 = 2,
}

MIDINotification :: struct {
	messageID:   MIDINotificationMessageID,
	messageSize: u32,
}

MIDIEventPacket :: struct {
	timeStamp: MIDITimeStamp,
	wordCount: u32,
	words:     [64]u32,
}

MIDIEventList :: struct {
	protocol:   MIDIProtocolID,
	numPackets: u32,
	packet:     [1]MIDIEventPacket,
}

MIDINotifyProc :: proc "c" (message: ^MIDINotification, refCon: rawptr)
MIDIReceiveProc :: proc "c" (event_list: ^MIDIEventList, cntxt: rawptr, source_cntxt: rawptr)

foreign core_midi_bridge {
	mohg_midi_input_port_create :: proc(client: MIDIClientRef, port_name: CFStringRef, protocol: MIDIProtocolID, out_port: ^MIDIPortRef, cntxt: rawptr, receive_proc: MIDIReceiveProc) -> OSStatus ---
}

foreign CoreMIDI {
	MIDIClientCreate :: proc(name: CFStringRef, notifyProc: MIDINotifyProc, notifyRefCon: rawptr, outClient: ^MIDIClientRef) -> OSStatus ---
	MIDIGetNumberOfSources :: proc() -> ItemCount ---
	MIDIGetSource :: proc(_: ItemCount) -> MIDIEndpointRef ---
	MIDIPortConnectSource :: proc(port: MIDIPortRef, source: MIDIEndpointRef, connRefCon: rawptr) -> OSStatus ---
}

fill_midi_queue :: proc "c" (event_list: ^MIDIEventList, cntxt: rawptr, source_cntxt: rawptr) {
	queue := cast(^Spsc_Queue(Midi_Event, MIDI_QUEUE_CAPACITY))cntxt

	packet := &event_list.packet[0]
	for _ in 0 ..< int(event_list.numPackets) {
		word_count := int(packet.wordCount)
		words := cast([^]u32)(&packet.words[0])

		for word_index in 0 ..< word_count {
			word := words[word_index]

			message_type := (word >> 28) & 0xf
			if message_type != 0x2 {
				continue
			}

			status := u8((word >> 16) & 0xff)
			kind := status & 0xf0
			channel := status & 0x0f
			note := u8((word >> 8) & 0x7f)
			velocity := u8(word & 0x7f)


			event := Midi_Event {
				kind     = Midi_Event_Kind.Note_Off,
				channel  = channel,
				note     = note,
				velocity = velocity,
			}
			switch kind {
			case 0x80:
				event.kind = .Note_Off

			case 0x90:
				event.kind = velocity == 0 ? .Note_Off : .Note_On

			case:
				continue
			}


			_ = spsc_try_push(queue, event)
		}

		packet = cast(^MIDIEventPacket)(&words[word_count])
	}

}

Midi_Input :: struct {
	client: MIDIClientRef,
	port:   MIDIPortRef,
}


midi_input_init :: proc(
	midi: ^Midi_Input,
	queue: ^Spsc_Queue(Midi_Event, MIDI_QUEUE_CAPACITY),
) -> OSStatus {
	name := CFStringCreateWithCString(nil, cstring("mohg"), kCFStringEncodingUTF8)
	port_name := CFStringCreateWithCString(nil, cstring("port"), kCFStringEncodingUTF8)

	if name == nil {
		return 1
	}

	if port_name == nil {
		return 1
	}

	defer CFRelease(name)
	defer CFRelease(port_name)

	status := MIDIClientCreate(name, nil, nil, &midi.client)
	if (status != 0) {
		return 1
	}

	status = mohg_midi_input_port_create(
		midi.client,
		port_name,
		MIDIProtocolID.kMIDIProtocol_1_0,
		&midi.port,
		rawptr(queue),
		fill_midi_queue,
	)

	if (status != 0) {
		return 1
	}

	source_count := MIDIGetNumberOfSources()

	if source_count == 0 {
		return 1
	}


	connected := false
	for i in 0 ..< source_count {
		source := MIDIGetSource(i)

		connect_status := MIDIPortConnectSource(midi.port, source, nil)
		if connect_status != 0 {
			fmt.printfln("failed to connect to source index %v", i)
		} else {
			fmt.printfln("connected to source index %v", i)
			connected = true
			break
		}
	}

	return connected ? 0 : 1
}

midi_input_destroy :: proc() {
	// destroy midi
}
