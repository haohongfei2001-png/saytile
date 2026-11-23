// A deterministic 2/3-core integer workload. SIGTERM emits a per-PID receipt.
// Build once before sampling: cc -O2 preview-cpu-load.c -o preview-cpu-load
#include <inttypes.h>
#include <pthread.h>
#include <pthread/qos.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

static volatile sig_atomic_t running = 1;

static void stop(int signal_number) {
    (void)signal_number;
    running = 0;
}

static double seconds(clockid_t clock_id) {
    struct timespec t;
    if (clock_gettime(clock_id, &t) != 0) {
        perror("clock_gettime");
        exit(1);
    }
    return (double)t.tv_sec + (double)t.tv_nsec / 1e9;
}

int main(void) {
    signal(SIGTERM, stop);
    // Give the benchmark load access to performance cores when the invoking
    // noninteractive shell was assigned background/utility QoS.
    if (pthread_set_qos_class_self_np(QOS_CLASS_USER_INITIATED, 0) != 0) {
        fputs("Cannot set load worker QoS\n", stderr);
        return 1;
    }
    double start_wall = seconds(CLOCK_MONOTONIC);
    double start_cpu = seconds(CLOCK_PROCESS_CPUTIME_ID);
    unsigned periods = 0;
    volatile uint64_t checksum = 104729;
    while (running) {
        ++periods;
        double target = start_cpu + periods * 0.040;
        double deadline = start_wall + periods * 0.060;
        while (running && seconds(CLOCK_PROCESS_CPUTIME_ID) < target) {
            for (unsigned i = 0; i < 2048; ++i) {
                checksum = checksum * 1664525 + 1013904223;
            }
        }
        double remaining = deadline - seconds(CLOCK_MONOTONIC);
        if (running && remaining > 0) {
            struct timespec pause = {.tv_nsec = (long)(remaining * 1e9)};
            nanosleep(&pause, NULL);
        }
    }
    printf("{\"pid\":%d,\"cpu_s\":%.6f,\"wall_s\":%.6f,\"periods\":%u,\"checksum\":%" PRIu64 "}\n",
           getpid(), seconds(CLOCK_PROCESS_CPUTIME_ID) - start_cpu,
           seconds(CLOCK_MONOTONIC) - start_wall, periods, checksum);
    return 0;
}
