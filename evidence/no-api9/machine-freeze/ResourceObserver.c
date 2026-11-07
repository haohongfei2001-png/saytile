#include <libproc.h>
#include <sys/resource.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

/* The caller supplies only its own Saytile test PID. Counters contain no user samples. */
int main(int argc, char **argv) {
    if (argc != 3) return 64;
    const pid_t pid = (pid_t)strtol(argv[1], NULL, 10);
    const time_t deadline = (time_t)strtoll(argv[2], NULL, 10);
    if (pid <= 0 || deadline <= time(NULL)) return 64;
    uint64_t start_id = 0;
    do {
        struct rusage_info_v6 info = {0};
        if (proc_pid_rusage(pid, RUSAGE_INFO_V6, (rusage_info_t *)&info)) break;
        if (start_id && start_id != info.ri_proc_start_abstime) return 2;
        start_id = info.ri_proc_start_abstime;
        printf("{\"unix\":%lld,\"start_abstime\":%llu,\"user_ns\":%llu,\"system_ns\":%llu,\"footprint_bytes\":%llu,\"peak_footprint_bytes\":%llu,\"disk_written_bytes\":%llu,\"reported_energy_nj\":%llu,\"idle_wakeups\":%llu}\n",
               (long long)time(NULL), info.ri_proc_start_abstime, info.ri_user_time, info.ri_system_time,
               info.ri_phys_footprint, info.ri_lifetime_max_phys_footprint, info.ri_diskio_byteswritten, info.ri_energy_nj, info.ri_pkg_idle_wkups);
        fflush(stdout);
        sleep(60);
    } while (time(NULL) < deadline);
    return start_id == 0;
}
