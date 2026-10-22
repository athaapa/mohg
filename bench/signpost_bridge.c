#include <os/log.h>
#include <os/signpost.h>
#include <stdint.h>

// Called only by the benchmark's main thread, before measured work.
void *mohg_bench_signpost_log(void) {
    static os_log_t log;
    if (!log) {
        log = os_log_create("mohg.bench", OS_LOG_CATEGORY_POINTS_OF_INTEREST);
    }
    return log;
}

uint64_t mohg_bench_signpost_begin(void *handle, const char *phase,
                                  int32_t n, int32_t k, int32_t l,
                                  int32_t f, int32_t b) {
    os_log_t log = (os_log_t)handle;
    os_signpost_id_t id = os_signpost_id_generate(log);
    os_signpost_interval_begin(log, id, "Render blocks",
        "phase=%{public}s n=%d k=%d L=%d F=%d B=%d", phase, n, k, l, f, b);
    return id;
}

void mohg_bench_signpost_end(void *handle, uint64_t id) {
    os_signpost_interval_end((os_log_t)handle, id, "Render blocks");
}
