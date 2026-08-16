#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define MSR_IA32_THERM_STATUS 0x19c
#define MSR_IA32_PERF_STATUS 0x198
#define MSR_POWER_CTL 0x1fc
#define BD_PROCHOT_ENABLE UINT64_C(1)

enum mode {
    MODE_STATUS,
    MODE_DISABLE,
    MODE_ENABLE,
};

static void usage(FILE *stream, const char *program) {
    fprintf(stream,
            "Usage: %s [status|disable|enable]\n"
            "\n"
            "  status   Read BD PROCHOT, PROCHOT and thermal status (default)\n"
            "  disable  Clear only the bidirectional PROCHOT enable bit\n"
            "  enable   Restore the bidirectional PROCHOT enable bit\n",
            program);
}

static int read_msr(int fd, off_t address, uint64_t *value) {
    ssize_t count = pread(fd, value, sizeof(*value), address);
    if (count == (ssize_t)sizeof(*value)) return 0;
    if (count >= 0) errno = EIO;
    return -1;
}

static int write_msr(int fd, off_t address, uint64_t value) {
    ssize_t count = pwrite(fd, &value, sizeof(value), address);
    if (count == (ssize_t)sizeof(value)) return 0;
    if (count >= 0) errno = EIO;
    return -1;
}

static int show_status(int fd, int cpu) {
    uint64_t power_ctl = 0;
    uint64_t therm_status = 0;
    uint64_t perf_status = 0;

    if (read_msr(fd, MSR_POWER_CTL, &power_ctl) < 0 ||
        read_msr(fd, MSR_IA32_THERM_STATUS, &therm_status) < 0 ||
        read_msr(fd, MSR_IA32_PERF_STATUS, &perf_status) < 0) {
        fprintf(stderr, "cpu%d: read failed: %s\n", cpu, strerror(errno));
        return -1;
    }

    printf("cpu%d bd_prochot=%s thermal=%s prochot_or_forcepr=%s "
           "ratio=0x%02" PRIx64 " power_ctl=0x%016" PRIx64
           " therm_status=0x%016" PRIx64 "\n",
           cpu,
           (power_ctl & BD_PROCHOT_ENABLE) ? "enabled" : "disabled",
           (therm_status & UINT64_C(1)) ? "active" : "inactive",
           (therm_status & UINT64_C(1) << 2) ? "active" : "inactive",
           (perf_status >> 8) & UINT64_C(0xff),
           power_ctl,
           therm_status);
    return 0;
}

static int change_bd_prochot(int fd, int cpu, int enable) {
    uint64_t before = 0;
    uint64_t after = 0;

    if (read_msr(fd, MSR_POWER_CTL, &before) < 0) {
        fprintf(stderr, "cpu%d: read MSR_POWER_CTL: %s\n", cpu, strerror(errno));
        return -1;
    }

    uint64_t requested = enable ? before | BD_PROCHOT_ENABLE
                                : before & ~BD_PROCHOT_ENABLE;
    if (write_msr(fd, MSR_POWER_CTL, requested) < 0) {
        fprintf(stderr, "cpu%d: write MSR_POWER_CTL: %s\n", cpu, strerror(errno));
        return -1;
    }
    if (read_msr(fd, MSR_POWER_CTL, &after) < 0) {
        fprintf(stderr, "cpu%d: verify MSR_POWER_CTL: %s\n", cpu, strerror(errno));
        return -1;
    }

    printf("cpu%d before=0x%016" PRIx64 " after=0x%016" PRIx64
           " bd_prochot=%s\n",
           cpu, before, after,
           (after & BD_PROCHOT_ENABLE) ? "enabled" : "disabled");
    return after == requested ? 0 : -1;
}

int main(int argc, char **argv) {
    enum mode mode = MODE_STATUS;

    if (argc == 2) {
        if (strcmp(argv[1], "status") == 0) {
            mode = MODE_STATUS;
        } else if (strcmp(argv[1], "disable") == 0) {
            mode = MODE_DISABLE;
        } else if (strcmp(argv[1], "enable") == 0) {
            mode = MODE_ENABLE;
        } else if (strcmp(argv[1], "--help") == 0 ||
                   strcmp(argv[1], "-h") == 0) {
            usage(stdout, argv[0]);
            return EXIT_SUCCESS;
        } else {
            usage(stderr, argv[0]);
            return EXIT_FAILURE;
        }
    } else if (argc != 1) {
        usage(stderr, argv[0]);
        return EXIT_FAILURE;
    }

    long cpu_count = sysconf(_SC_NPROCESSORS_CONF);
    if (cpu_count < 1) cpu_count = 1;

    int attempted = 0;
    int failed = 0;
    for (long cpu = 0; cpu < cpu_count; cpu++) {
        char path[64];
        snprintf(path, sizeof(path), "/dev/cpu/%ld/msr", cpu);
        int flags = mode == MODE_STATUS ? O_RDONLY : O_RDWR;
        int fd = open(path, flags | O_CLOEXEC);
        if (fd < 0) {
            if (errno == ENOENT || errno == ENXIO) continue;
            fprintf(stderr, "%s: %s\n", path, strerror(errno));
            failed = 1;
            continue;
        }

        attempted++;
        int result = mode == MODE_STATUS
                         ? show_status(fd, (int)cpu)
                         : change_bd_prochot(fd, (int)cpu, mode == MODE_ENABLE);
        if (result < 0) failed = 1;
        close(fd);
    }

    if (attempted == 0) {
        fprintf(stderr,
                "No CPU MSR devices were available. Run as root after loading "
                "the msr module.\n");
        return EXIT_FAILURE;
    }
    return failed ? EXIT_FAILURE : EXIT_SUCCESS;
}
