package mohg

import "core:fmt"

LOG_LINE_CAP :: 96
LOG_QUEUE_CAPACITY :: 128

Log_Text :: struct {
	len:  u16,
	text: [LOG_LINE_CAP]u8,
}

Log_Int :: struct {
	value: i64,
}

Log_Line :: union {
	Log_Text,
	Log_Int,
}

Log_Queue :: Spsc_Queue(Log_Line, LOG_QUEUE_CAPACITY)

log_message :: proc "contextless" (queue: ^Log_Queue, message: string) {
	text: Log_Text
	n := min(len(message), LOG_LINE_CAP)
	for i in 0 ..< n {
		text.text[i] = message[i]
	}
	text.len = u16(n)

	line: Log_Line = text
	_ = spsc_try_push(queue, line)
}

log_int :: proc "contextless" (queue: ^Log_Queue, value: i64) {
	line: Log_Line = Log_Int {
		value = value,
	}
	_ = spsc_try_push(queue, line)
}

log_drain :: proc(queue: ^Log_Queue) {
	for {
		event, ok := spsc_try_pop(queue)
		if !ok {
			break
		}

		switch line in event {
		case Log_Text:
			text := line
			fmt.println(string(text.text[:text.len]))
		case Log_Int:
			fmt.println(line.value)
		}
	}
}
