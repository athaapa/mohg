#include <CoreMIDI/CoreMIDI.h>

typedef void (*MohgMIDIReceiveProc)(const MIDIEventList *eventList,
                                    void *context, void *sourceContext);

OSStatus mohg_midi_input_port_create(MIDIClientRef client, CFStringRef portName,
                                     MIDIProtocolID protocol,
                                     MIDIPortRef *outPort, void *context,
                                     MohgMIDIReceiveProc receiveProc) {
  return MIDIInputPortCreateWithProtocol(
      client, portName, protocol, outPort,
      ^(const MIDIEventList *eventList, void *sourceContext) {
        receiveProc(eventList, context, sourceContext);
      });
}
