/*
 * Minimal full-OS boot example for libkrun.
 *
 * This boots a prepared Linux root disk through direct kernel boot. The guest
 * kernel must include virtio-mmio and virtio-blk support, and the root device
 * passed with --root-device must exist inside the guest.
 */

#include <errno.h>
#include <ctype.h>
#include <getopt.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

#include <libkrun.h>

#if defined(__x86_64__)
#define DEFAULT_KERNEL_FORMAT KRUN_KERNEL_FORMAT_ELF
#define DEFAULT_CONSOLE "ttyS0"
#elif defined(__aarch64__) || defined(__arm64__)
#define DEFAULT_KERNEL_FORMAT KRUN_KERNEL_FORMAT_PE_GZ
#define DEFAULT_CONSOLE "ttyAMA0"
#else
#define DEFAULT_KERNEL_FORMAT KRUN_KERNEL_FORMAT_RAW
#define DEFAULT_CONSOLE "hvc0"
#endif

#define MAX_KERNEL_FORMAT KRUN_KERNEL_FORMAT_IMAGE_ZSTD
#define MAX_VIRTIOFS_MOUNTS 8

struct virtiofs_mount {
    char *tag;
    char *path;
    bool read_only;
};

struct cmdline {
    const char *kernel_path;
    const char *root_disk;
    const char *root_device;
    const char *root_fstype;
    const char *root_options;
    const char *guest_init;
    const char *initramfs_path;
    const char *kernel_cmdline;
    const char *console;
    const char *passt_socket;
    const char *gvproxy_socket;
    const char *control_socket;
    struct virtiofs_mount virtiofs_mounts[MAX_VIRTIOFS_MOUNTS];
    uint64_t virtiofs_dax_size;
    uint32_t net_features;
    uint32_t kernel_format;
    uint32_t disk_sync_mode;
    uint32_t ram_mib;
    uint32_t balloon_initial_mib;
    uint32_t balloon_min_mib;
    size_t virtiofs_mount_count;
    uint8_t num_vcpus;
    bool gvproxy_vfkit_magic;
    bool poweroff_after_ready;
    bool serial_pty;
    bool show_help;
};

struct serial_pty_bridge {
    int master_fd;
    int slave_fd;
    int wake_pipe[2];
    pthread_t thread;
    struct termios host_old_termios;
    bool host_raw_enabled;
    bool thread_started;
};

static void print_help(const char *name)
{
    fprintf(stderr,
            "Usage: %s [OPTIONS] --kernel PATH --root-disk PATH\n"
            "\n"
            "Options:\n"
            "  -k, --kernel PATH          Guest kernel image\n"
            "  -d, --root-disk PATH       Raw root disk image\n"
            "  -r, --root-device DEVICE   Guest root device (default: /dev/vda1)\n"
            "  -t, --root-fstype FSTYPE   Root filesystem type (default: ext4)\n"
            "  -o, --root-options OPTS    Root mount options\n"
            "      --guest-init PATH      Guest init path (default: /sbin/init)\n"
            "  -i, --initramfs PATH       Optional initramfs image\n"
            "  -c, --kernel-cmdline TEXT  Extra kernel command line\n"
            "  -C, --console NAME         Kernel console name (default: " DEFAULT_CONSOLE ")\n"
            "  -P, --passt-socket PATH    Connect virtio-net to a passt unixstream socket\n"
            "  -G, --gvproxy-socket PATH  Connect virtio-net to a gvproxy/vfkit unixgram socket\n"
            "  -V, --virtiofs TAG=PATH    Add a non-root virtio-fs shared directory\n"
            "      --virtiofs-ro TAG=PATH Add a read-only non-root virtio-fs shared directory\n"
            "      --virtiofs-dax-size NUM  DAX window bytes for virtio-fs mounts (default: 0 = off)\n"
            "      --cpus NUM             Number of guest vCPUs (default: 2)\n"
            "      --memory-mib NUM       Guest RAM in MiB (default: 2048); the resize ceiling\n"
            "      --balloon-initial-mib NUM  Initial guest usable RAM in MiB (enables resize; <= --memory-mib)\n"
            "      --balloon-min-mib NUM  Floor for runtime memory reclaim in MiB (default: 0)\n"
            "      --control-socket PATH  Unix socket for runtime memory-resize commands\n"
            "      --disk-sync MODE       Root disk sync mode: relaxed, full, none, or 0-2 (default: relaxed)\n"
            "      --gvproxy-vfkit-magic  Send legacy VFKT magic before Ethernet frames\n"
            "      --net-features NUM     Virtio-net feature mask (default: COMPAT_NET_FEATURES)\n"
            "      --poweroff-after-ready Append the validation-only readiness poweroff marker\n"
            "      --serial-pty           Bridge host stdio through a PTY-backed serial console\n"
            "  -f, --kernel-format NUM    KRUN_KERNEL_FORMAT_* value (default is arch-specific)\n"
            "  -h, --help                 Show this help\n",
            name);
}

static bool parse_u32(const char *value, uint32_t *out)
{
    char *end = NULL;
    unsigned long parsed = strtoul(value, &end, 0);
    if (end == value || *end != '\0' || parsed > UINT32_MAX) {
        return false;
    }
    *out = (uint32_t)parsed;
    return true;
}

static bool parse_u64(const char *value, uint64_t *out)
{
    char *end = NULL;
    unsigned long long parsed = strtoull(value, &end, 0);
    if (end == value || *end != '\0') {
        return false;
    }
    *out = (uint64_t)parsed;
    return true;
}

static bool parse_u8(const char *value, uint8_t *out)
{
    uint32_t parsed = 0;
    if (!parse_u32(value, &parsed) || parsed > UINT8_MAX) {
        return false;
    }
    *out = (uint8_t)parsed;
    return true;
}

static bool parse_disk_sync_mode(const char *value, uint32_t *out)
{
    if (strcmp(value, "none") == 0) {
        *out = KRUN_SYNC_NONE;
        return true;
    }
    if (strcmp(value, "relaxed") == 0) {
        *out = KRUN_SYNC_RELAXED;
        return true;
    }
    if (strcmp(value, "full") == 0) {
        *out = KRUN_SYNC_FULL;
        return true;
    }

    uint32_t parsed = 0;
    if (!parse_u32(value, &parsed) || parsed > KRUN_SYNC_FULL) {
        return false;
    }
    *out = parsed;
    return true;
}

static bool is_kernel_cmdline_token(const char *value)
{
    if (value == NULL || value[0] == '\0') {
        return false;
    }
    for (const unsigned char *p = (const unsigned char *)value; *p != '\0'; p++) {
        if (isspace(*p)) {
            return false;
        }
    }
    return true;
}

static bool validate_kernel_cmdline_token(const char *name, const char *value)
{
    if (is_kernel_cmdline_token(value)) {
        return true;
    }
    fprintf(stderr, "%s must be a non-empty single kernel command-line token\n", name);
    return false;
}

static bool validate_optional_kernel_cmdline_token(const char *name, const char *value)
{
    if (value == NULL) {
        return true;
    }
    return validate_kernel_cmdline_token(name, value);
}

static bool validate_non_empty_arg(const char *name, const char *value)
{
    if (value != NULL && value[0] != '\0') {
        return true;
    }
    fprintf(stderr, "%s must be non-empty\n", name);
    return false;
}

static bool validate_optional_non_empty_arg(const char *name, const char *value)
{
    if (value == NULL) {
        return true;
    }
    return validate_non_empty_arg(name, value);
}

static void free_virtiofs_mounts(struct cmdline *cmdline)
{
    for (size_t i = 0; i < cmdline->virtiofs_mount_count; i++) {
        free(cmdline->virtiofs_mounts[i].tag);
        free(cmdline->virtiofs_mounts[i].path);
        cmdline->virtiofs_mounts[i].tag = NULL;
        cmdline->virtiofs_mounts[i].path = NULL;
    }
    cmdline->virtiofs_mount_count = 0;
}

static bool parse_virtiofs_mount(const char *value, bool read_only, struct virtiofs_mount *out)
{
    const char *separator = strchr(value, '=');
    if (separator == NULL || separator == value || separator[1] == '\0') {
        fprintf(stderr, "--virtiofs must use TAG=PATH with non-empty values\n");
        return false;
    }

    size_t tag_len = (size_t)(separator - value);
    out->tag = malloc(tag_len + 1);
    out->path = strdup(separator + 1);
    out->read_only = read_only;
    if (out->tag == NULL || out->path == NULL) {
        free(out->tag);
        free(out->path);
        out->tag = NULL;
        out->path = NULL;
        fprintf(stderr, "Failed to allocate --virtiofs mount\n");
        return false;
    }

    memcpy(out->tag, value, tag_len);
    out->tag[tag_len] = '\0';
    return true;
}

/* Long-only option values must sit above the ASCII range used by short opts. */
#define OPT_VIRTIOFS_DAX_SIZE 1000

static bool parse_cmdline(int argc, char *const argv[], struct cmdline *cmdline)
{
    static const struct option long_options[] = {
        {"kernel", required_argument, NULL, 'k'},
        {"root-disk", required_argument, NULL, 'd'},
        {"root-device", required_argument, NULL, 'r'},
        {"root-fstype", required_argument, NULL, 't'},
        {"root-options", required_argument, NULL, 'o'},
        {"guest-init", required_argument, NULL, 'I'},
        {"initramfs", required_argument, NULL, 'i'},
        {"kernel-cmdline", required_argument, NULL, 'c'},
        {"console", required_argument, NULL, 'C'},
        {"passt-socket", required_argument, NULL, 'P'},
        {"gvproxy-socket", required_argument, NULL, 'G'},
        {"virtiofs", required_argument, NULL, 'V'},
        {"virtiofs-ro", required_argument, NULL, 'R'},
        {"virtiofs-dax-size", required_argument, NULL, OPT_VIRTIOFS_DAX_SIZE},
        {"cpus", required_argument, NULL, 'u'},
        {"memory-mib", required_argument, NULL, 'M'},
        {"balloon-initial-mib", required_argument, NULL, 'A'},
        {"balloon-min-mib", required_argument, NULL, 'N'},
        {"control-socket", required_argument, NULL, 'K'},
        {"disk-sync", required_argument, NULL, 'S'},
        {"gvproxy-vfkit-magic", no_argument, NULL, 'm'},
        {"net-features", required_argument, NULL, 'F'},
        {"poweroff-after-ready", no_argument, NULL, 'p'},
        {"serial-pty", no_argument, NULL, 'Y'},
        {"kernel-format", required_argument, NULL, 'f'},
        {"help", no_argument, NULL, 'h'},
        {NULL, 0, NULL, 0},
    };

    *cmdline = (struct cmdline){
        .kernel_path = NULL,
        .root_disk = NULL,
        .root_device = "/dev/vda1",
        .root_fstype = "ext4",
        .root_options = NULL,
        .guest_init = NULL,
        .initramfs_path = NULL,
        .kernel_cmdline = NULL,
        .console = DEFAULT_CONSOLE,
        .passt_socket = NULL,
        .gvproxy_socket = NULL,
        .control_socket = NULL,
        .net_features = COMPAT_NET_FEATURES,
        .kernel_format = DEFAULT_KERNEL_FORMAT,
        .disk_sync_mode = KRUN_SYNC_RELAXED,
        .ram_mib = 2048,
        .balloon_initial_mib = 0,
        .balloon_min_mib = 0,
        .virtiofs_mount_count = 0,
        .virtiofs_dax_size = 0,
        .num_vcpus = 2,
        .gvproxy_vfkit_magic = false,
        .poweroff_after_ready = false,
        .serial_pty = false,
        .show_help = false,
    };

    int option_index = 0;
    int c;
    while ((c = getopt_long(argc, argv, "hk:d:r:t:o:i:c:C:P:G:V:f:", long_options, &option_index)) != -1) {
        switch (c) {
        case 'k':
            cmdline->kernel_path = optarg;
            break;
        case 'd':
            cmdline->root_disk = optarg;
            break;
        case 'r':
            cmdline->root_device = optarg;
            break;
        case 't':
            cmdline->root_fstype = optarg;
            break;
        case 'o':
            cmdline->root_options = optarg;
            break;
        case 'I':
            cmdline->guest_init = optarg;
            break;
        case 'i':
            cmdline->initramfs_path = optarg;
            break;
        case 'c':
            cmdline->kernel_cmdline = optarg;
            break;
        case 'C':
            cmdline->console = optarg;
            break;
        case 'P':
            cmdline->passt_socket = optarg;
            break;
        case 'G':
            cmdline->gvproxy_socket = optarg;
            break;
        case 'V':
            if (cmdline->virtiofs_mount_count >= MAX_VIRTIOFS_MOUNTS) {
                fprintf(stderr, "Too many --virtiofs mounts; maximum is %d\n", MAX_VIRTIOFS_MOUNTS);
                return false;
            }
            if (!parse_virtiofs_mount(optarg,
                                      false,
                                      &cmdline->virtiofs_mounts[cmdline->virtiofs_mount_count])) {
                return false;
            }
            cmdline->virtiofs_mount_count++;
            break;
        case 'R':
            if (cmdline->virtiofs_mount_count >= MAX_VIRTIOFS_MOUNTS) {
                fprintf(stderr, "Too many virtio-fs mounts; maximum is %d\n", MAX_VIRTIOFS_MOUNTS);
                return false;
            }
            if (!parse_virtiofs_mount(optarg,
                                      true,
                                      &cmdline->virtiofs_mounts[cmdline->virtiofs_mount_count])) {
                return false;
            }
            cmdline->virtiofs_mount_count++;
            break;
        case OPT_VIRTIOFS_DAX_SIZE:
            if (!parse_u64(optarg, &cmdline->virtiofs_dax_size)) {
                fprintf(stderr, "Invalid virtio-fs DAX window size: %s\n", optarg);
                return false;
            }
            break;
        case 'u':
            if (!parse_u8(optarg, &cmdline->num_vcpus) || cmdline->num_vcpus == 0) {
                fprintf(stderr, "Invalid vCPU count: %s\n", optarg);
                return false;
            }
            break;
        case 'M':
            if (!parse_u32(optarg, &cmdline->ram_mib) || cmdline->ram_mib == 0) {
                fprintf(stderr, "Invalid memory size: %s\n", optarg);
                return false;
            }
            break;
        case 'A':
            if (!parse_u32(optarg, &cmdline->balloon_initial_mib) ||
                cmdline->balloon_initial_mib == 0) {
                fprintf(stderr, "Invalid balloon initial memory size: %s\n", optarg);
                return false;
            }
            break;
        case 'N':
            if (!parse_u32(optarg, &cmdline->balloon_min_mib)) {
                fprintf(stderr, "Invalid balloon min memory size: %s\n", optarg);
                return false;
            }
            break;
        case 'K':
            cmdline->control_socket = optarg;
            break;
        case 'S':
            if (!parse_disk_sync_mode(optarg, &cmdline->disk_sync_mode)) {
                fprintf(stderr, "Invalid disk sync mode: %s\n", optarg);
                return false;
            }
            break;
        case 'm':
            cmdline->gvproxy_vfkit_magic = true;
            break;
        case 'p':
            cmdline->poweroff_after_ready = true;
            break;
        case 'Y':
            cmdline->serial_pty = true;
            break;
        case 'F':
            if (!parse_u32(optarg, &cmdline->net_features)) {
                fprintf(stderr, "Invalid network feature mask: %s\n", optarg);
                return false;
            }
            break;
        case 'f':
            if (!parse_u32(optarg, &cmdline->kernel_format) ||
                cmdline->kernel_format > MAX_KERNEL_FORMAT) {
                fprintf(stderr, "Invalid kernel format: %s\n", optarg);
                return false;
            }
            break;
        case 'h':
            cmdline->show_help = true;
            return true;
        default:
            return false;
        }
    }

    if (optind < argc) {
        fprintf(stderr, "Unexpected argument: %s\n", argv[optind]);
        return false;
    }
    if (cmdline->kernel_path == NULL) {
        fprintf(stderr, "Missing --kernel\n");
        return false;
    }
    if (cmdline->root_disk == NULL) {
        fprintf(stderr, "Missing --root-disk\n");
        return false;
    }
    if (!validate_non_empty_arg("--kernel", cmdline->kernel_path) ||
        !validate_non_empty_arg("--root-disk", cmdline->root_disk) ||
        !validate_optional_non_empty_arg("--initramfs", cmdline->initramfs_path) ||
        !validate_optional_non_empty_arg("--passt-socket", cmdline->passt_socket) ||
        !validate_optional_non_empty_arg("--gvproxy-socket", cmdline->gvproxy_socket)) {
        return false;
    }
    if (cmdline->passt_socket != NULL && cmdline->gvproxy_socket != NULL) {
        fprintf(stderr, "--passt-socket and --gvproxy-socket are mutually exclusive\n");
        return false;
    }
    if (!validate_kernel_cmdline_token("--root-device", cmdline->root_device) ||
        !validate_kernel_cmdline_token("--root-fstype", cmdline->root_fstype) ||
        !validate_optional_kernel_cmdline_token("--root-options", cmdline->root_options) ||
        !validate_optional_kernel_cmdline_token("--guest-init", cmdline->guest_init) ||
        !validate_kernel_cmdline_token("--console", cmdline->console)) {
        return false;
    }
    return true;
}

#ifdef OS_MODE_PARSE_SELFTEST
static void reset_getopt_state(void)
{
    optind = 1;
#if defined(__APPLE__) || defined(__FreeBSD__)
    optreset = 1;
#endif
}

static bool expect_parse_success(int argc, char *const argv[], struct cmdline *out)
{
    reset_getopt_state();
    return parse_cmdline(argc, argv, out);
}

static bool expect_parse_failure(int argc, char *const argv[])
{
    struct cmdline ignored;

    reset_getopt_state();
    return !parse_cmdline(argc, argv, &ignored);
}

static bool expect_token(const char *value, bool expected)
{
    return is_kernel_cmdline_token(value) == expected;
}

static bool run_parse_selftest(void)
{
    if (!expect_token("ext4", true) ||
        !expect_token("/dev/vda1", true) ||
        !expect_token("PARTUUID=abcd-01", true) ||
        !expect_token("rw,noatime", true) ||
        !expect_token(NULL, false) ||
        !expect_token("", false) ||
        !expect_token("ext4 quiet", false) ||
        !expect_token("rw\tnoatime", false)) {
        fprintf(stderr, "token validation self-test failed\n");
        return false;
    }

    char *valid[] = {
        "os_mode_parse_selftest",
        "--kernel", "kernel.img",
        "--root-disk", "root.raw",
        "--root-device", "PARTUUID=abcd-01",
        "--root-fstype", "ext4",
        "--root-options", "rw,noatime",
        "--guest-init", "/sbin/init",
        "--console", "ttyAMA0",
        "--virtiofs", "react-app=/Users/example/react-app",
        "--virtiofs-ro", "credentials=/Users/example/credentials",
        "--cpus", "4",
        "--memory-mib", "4096",
        "--kernel-format", "2",
        "--disk-sync", "full",
        "--net-features", "1",
        "--gvproxy-vfkit-magic",
        "--poweroff-after-ready",
        "--serial-pty",
        "--kernel-cmdline", "panic=-1 reboot=k",
    };
    struct cmdline cmdline;
    if (!expect_parse_success((int)(sizeof(valid) / sizeof(valid[0])), valid, &cmdline)) {
        fprintf(stderr, "valid command line self-test failed\n");
        return false;
    }
    if (strcmp(cmdline.kernel_path, "kernel.img") != 0 ||
        strcmp(cmdline.root_disk, "root.raw") != 0 ||
        strcmp(cmdline.root_device, "PARTUUID=abcd-01") != 0 ||
        strcmp(cmdline.root_fstype, "ext4") != 0 ||
        strcmp(cmdline.root_options, "rw,noatime") != 0 ||
        strcmp(cmdline.guest_init, "/sbin/init") != 0 ||
        strcmp(cmdline.console, "ttyAMA0") != 0 ||
        cmdline.virtiofs_mount_count != 2 ||
        strcmp(cmdline.virtiofs_mounts[0].tag, "react-app") != 0 ||
        strcmp(cmdline.virtiofs_mounts[0].path, "/Users/example/react-app") != 0 ||
        cmdline.virtiofs_mounts[0].read_only ||
        strcmp(cmdline.virtiofs_mounts[1].tag, "credentials") != 0 ||
        strcmp(cmdline.virtiofs_mounts[1].path, "/Users/example/credentials") != 0 ||
        !cmdline.virtiofs_mounts[1].read_only ||
        strcmp(cmdline.kernel_cmdline, "panic=-1 reboot=k") != 0 ||
        cmdline.kernel_format != KRUN_KERNEL_FORMAT_PE_GZ ||
        cmdline.disk_sync_mode != KRUN_SYNC_FULL ||
        cmdline.num_vcpus != 4 ||
        cmdline.ram_mib != 4096 ||
        cmdline.net_features != 1 ||
        !cmdline.gvproxy_vfkit_magic ||
        !cmdline.poweroff_after_ready ||
        !cmdline.serial_pty) {
        fprintf(stderr, "parsed command line fields self-test failed\n");
        return false;
    }

    char *bad_root_device[] = {
        "os_mode_parse_selftest", "--kernel", "kernel.img", "--root-disk", "root.raw",
        "--root-device", "/dev/vda quiet",
    };
    char *bad_root_fstype[] = {
        "os_mode_parse_selftest", "--kernel", "kernel.img", "--root-disk", "root.raw",
        "--root-fstype", "ext4 quiet",
    };
    char *bad_root_options[] = {
        "os_mode_parse_selftest", "--kernel", "kernel.img", "--root-disk", "root.raw",
        "--root-options", "rw noatime",
    };
    char *bad_guest_init[] = {
        "os_mode_parse_selftest", "--kernel", "kernel.img", "--root-disk", "root.raw",
        "--guest-init", "/sbin/init quiet",
    };
    char *bad_console[] = {
        "os_mode_parse_selftest", "--kernel", "kernel.img", "--root-disk", "root.raw",
        "--console", "ttyAMA0 earlycon",
    };
    char *bad_kernel_format[] = {
        "os_mode_parse_selftest", "--kernel", "kernel.img", "--root-disk", "root.raw",
        "--kernel-format", "6",
    };
    char *bad_disk_sync[] = {
        "os_mode_parse_selftest", "--kernel", "kernel.img", "--root-disk", "root.raw",
        "--disk-sync", "unsafe",
    };
    char *bad_cpus[] = {
        "os_mode_parse_selftest", "--kernel", "kernel.img", "--root-disk", "root.raw",
        "--cpus", "0",
    };
    char *bad_memory[] = {
        "os_mode_parse_selftest", "--kernel", "kernel.img", "--root-disk", "root.raw",
        "--memory-mib", "0",
    };
    char *bad_networks[] = {
        "os_mode_parse_selftest", "--kernel", "kernel.img", "--root-disk", "root.raw",
        "--passt-socket", "passt.sock", "--gvproxy-socket", "gvproxy.sock",
    };
    char *empty_kernel[] = {
        "os_mode_parse_selftest", "--kernel", "", "--root-disk", "root.raw",
    };
    char *empty_root_disk[] = {
        "os_mode_parse_selftest", "--kernel", "kernel.img", "--root-disk", "",
    };
    char *empty_initramfs[] = {
        "os_mode_parse_selftest", "--kernel", "kernel.img", "--root-disk", "root.raw",
        "--initramfs", "",
    };
    char *empty_passt_socket[] = {
        "os_mode_parse_selftest", "--kernel", "kernel.img", "--root-disk", "root.raw",
        "--passt-socket", "",
    };
    char *empty_gvproxy_socket[] = {
        "os_mode_parse_selftest", "--kernel", "kernel.img", "--root-disk", "root.raw",
        "--gvproxy-socket", "",
    };
    char *unexpected_argument[] = {
        "os_mode_parse_selftest", "--kernel", "kernel.img", "--root-disk", "root.raw",
        "extra.img",
    };
    char *bad_virtiofs_missing_separator[] = {
        "os_mode_parse_selftest", "--kernel", "kernel.img", "--root-disk", "root.raw",
        "--virtiofs", "react-app",
    };
    char *bad_virtiofs_empty_tag[] = {
        "os_mode_parse_selftest", "--kernel", "kernel.img", "--root-disk", "root.raw",
        "--virtiofs", "=/Users/example/react-app",
    };
    char *bad_virtiofs_empty_path[] = {
        "os_mode_parse_selftest", "--kernel", "kernel.img", "--root-disk", "root.raw",
        "--virtiofs", "react-app=",
    };
    char *bad_virtiofs_ro_missing_separator[] = {
        "os_mode_parse_selftest", "--kernel", "kernel.img", "--root-disk", "root.raw",
        "--virtiofs-ro", "credentials",
    };
    char *missing_kernel[] = {
        "os_mode_parse_selftest", "--root-disk", "root.raw",
    };
    char *missing_root_disk[] = {
        "os_mode_parse_selftest", "--kernel", "kernel.img",
    };

    if (!expect_parse_failure((int)(sizeof(bad_root_device) / sizeof(bad_root_device[0])), bad_root_device) ||
        !expect_parse_failure((int)(sizeof(bad_root_fstype) / sizeof(bad_root_fstype[0])), bad_root_fstype) ||
        !expect_parse_failure((int)(sizeof(bad_root_options) / sizeof(bad_root_options[0])), bad_root_options) ||
        !expect_parse_failure((int)(sizeof(bad_guest_init) / sizeof(bad_guest_init[0])), bad_guest_init) ||
        !expect_parse_failure((int)(sizeof(bad_console) / sizeof(bad_console[0])), bad_console) ||
        !expect_parse_failure((int)(sizeof(bad_kernel_format) / sizeof(bad_kernel_format[0])), bad_kernel_format) ||
        !expect_parse_failure((int)(sizeof(bad_disk_sync) / sizeof(bad_disk_sync[0])), bad_disk_sync) ||
        !expect_parse_failure((int)(sizeof(bad_cpus) / sizeof(bad_cpus[0])), bad_cpus) ||
        !expect_parse_failure((int)(sizeof(bad_memory) / sizeof(bad_memory[0])), bad_memory) ||
        !expect_parse_failure((int)(sizeof(bad_networks) / sizeof(bad_networks[0])), bad_networks) ||
        !expect_parse_failure((int)(sizeof(empty_kernel) / sizeof(empty_kernel[0])), empty_kernel) ||
        !expect_parse_failure((int)(sizeof(empty_root_disk) / sizeof(empty_root_disk[0])), empty_root_disk) ||
        !expect_parse_failure((int)(sizeof(empty_initramfs) / sizeof(empty_initramfs[0])), empty_initramfs) ||
        !expect_parse_failure((int)(sizeof(empty_passt_socket) / sizeof(empty_passt_socket[0])), empty_passt_socket) ||
        !expect_parse_failure((int)(sizeof(empty_gvproxy_socket) / sizeof(empty_gvproxy_socket[0])), empty_gvproxy_socket) ||
        !expect_parse_failure((int)(sizeof(unexpected_argument) / sizeof(unexpected_argument[0])), unexpected_argument) ||
        !expect_parse_failure((int)(sizeof(bad_virtiofs_missing_separator) / sizeof(bad_virtiofs_missing_separator[0])), bad_virtiofs_missing_separator) ||
        !expect_parse_failure((int)(sizeof(bad_virtiofs_empty_tag) / sizeof(bad_virtiofs_empty_tag[0])), bad_virtiofs_empty_tag) ||
        !expect_parse_failure((int)(sizeof(bad_virtiofs_empty_path) / sizeof(bad_virtiofs_empty_path[0])), bad_virtiofs_empty_path) ||
        !expect_parse_failure((int)(sizeof(bad_virtiofs_ro_missing_separator) / sizeof(bad_virtiofs_ro_missing_separator[0])), bad_virtiofs_ro_missing_separator) ||
        !expect_parse_failure((int)(sizeof(missing_kernel) / sizeof(missing_kernel[0])), missing_kernel) ||
        !expect_parse_failure((int)(sizeof(missing_root_disk) / sizeof(missing_root_disk[0])), missing_root_disk)) {
        fprintf(stderr, "invalid command line self-test failed\n");
        return false;
    }

    return true;
}

int main(void)
{
    return run_parse_selftest() ? 0 : 1;
}
#else
static const char *effective_kernel_cmdline(const struct cmdline *cmdline, char **owned)
{
    static const char poweroff_marker[] = "KRUN_OSMODE_POWEROFF=1";

    *owned = NULL;
    if (!cmdline->poweroff_after_ready) {
        return cmdline->kernel_cmdline;
    }
    if (cmdline->kernel_cmdline == NULL || cmdline->kernel_cmdline[0] == '\0') {
        return poweroff_marker;
    }

    size_t existing_len = strlen(cmdline->kernel_cmdline);
    size_t marker_len = strlen(poweroff_marker);
    char *combined = malloc(existing_len + 1 + marker_len + 1);
    if (combined == NULL) {
        return NULL;
    }
    memcpy(combined, cmdline->kernel_cmdline, existing_len);
    combined[existing_len] = ' ';
    memcpy(combined + existing_len + 1, poweroff_marker, marker_len + 1);
    *owned = combined;
    return combined;
}

static int report_error(const char *operation, int err)
{
    errno = -err;
    perror(operation);
    return 1;
}

static bool write_all(int fd, const unsigned char *buf, size_t len)
{
    while (len > 0) {
        ssize_t written = write(fd, buf, len);
        if (written < 0) {
            if (errno == EINTR) {
                continue;
            }
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                struct pollfd pfd = {
                    .fd = fd,
                    .events = POLLOUT,
                };
                if (poll(&pfd, 1, -1) < 0 && errno != EINTR) {
                    return false;
                }
                continue;
            }
            return false;
        }
        buf += written;
        len -= (size_t)written;
    }
    return true;
}

static void copy_winsize_to_pty(int slave_fd)
{
    struct winsize size = {
        .ws_row = 24,
        .ws_col = 80,
    };
    if (ioctl(STDIN_FILENO, TIOCGWINSZ, &size) == 0) {
        if (size.ws_row == 0) {
            size.ws_row = 24;
        }
        if (size.ws_col == 0) {
            size.ws_col = 80;
        }
    }
    (void)ioctl(slave_fd, TIOCSWINSZ, &size);
}

static void *serial_pty_bridge_thread(void *arg)
{
    struct serial_pty_bridge *bridge = arg;
    unsigned char buf[4096];

    for (;;) {
        struct pollfd fds[3] = {
            {.fd = STDIN_FILENO, .events = POLLIN},
            {.fd = bridge->master_fd, .events = POLLIN},
            {.fd = bridge->wake_pipe[0], .events = POLLIN},
        };
        copy_winsize_to_pty(bridge->slave_fd);

        int ready = poll(fds, 3, 1000);
        if (ready < 0) {
            if (errno == EINTR) {
                continue;
            }
            break;
        }
        if (ready == 0) {
            continue;
        }
        if (fds[2].revents) {
            break;
        }
        if (fds[0].revents & POLLIN) {
            ssize_t count = read(STDIN_FILENO, buf, sizeof(buf));
            if (count > 0) {
                (void)write_all(bridge->master_fd, buf, (size_t)count);
            } else if (count == 0 || (count < 0 && errno != EINTR && errno != EAGAIN)) {
                break;
            }
        }
        if (fds[1].revents & POLLIN) {
            ssize_t count = read(bridge->master_fd, buf, sizeof(buf));
            if (count > 0) {
                (void)write_all(STDOUT_FILENO, buf, (size_t)count);
            } else if (count == 0 || (count < 0 && errno != EINTR && errno != EAGAIN)) {
                break;
            }
        }
    }

    return NULL;
}

static bool set_raw_terminal(int fd, struct termios *old_termios)
{
    struct termios raw;
    if (tcgetattr(fd, old_termios) < 0) {
        return false;
    }
    raw = *old_termios;
    cfmakeraw(&raw);
    raw.c_lflag |= ISIG;
    return tcsetattr(fd, TCSANOW, &raw) == 0;
}

static bool setup_serial_pty_bridge(struct serial_pty_bridge *bridge)
{
    memset(bridge, 0, sizeof(*bridge));
    bridge->master_fd = -1;
    bridge->slave_fd = -1;
    bridge->wake_pipe[0] = -1;
    bridge->wake_pipe[1] = -1;

    bridge->master_fd = posix_openpt(O_RDWR | O_NOCTTY);
    if (bridge->master_fd < 0) {
        perror("posix_openpt");
        return false;
    }
    if (grantpt(bridge->master_fd) < 0 || unlockpt(bridge->master_fd) < 0) {
        perror("grantpt/unlockpt");
        return false;
    }

    char *slave_name = ptsname(bridge->master_fd);
    if (slave_name == NULL) {
        perror("ptsname");
        return false;
    }
    bridge->slave_fd = open(slave_name, O_RDWR | O_NOCTTY);
    if (bridge->slave_fd < 0) {
        perror("open pty slave");
        return false;
    }

    struct termios slave_termios;
    if (tcgetattr(bridge->slave_fd, &slave_termios) == 0) {
        cfmakeraw(&slave_termios);
        (void)tcsetattr(bridge->slave_fd, TCSANOW, &slave_termios);
    }
    copy_winsize_to_pty(bridge->slave_fd);

    if (isatty(STDIN_FILENO)) {
        bridge->host_raw_enabled = set_raw_terminal(STDIN_FILENO, &bridge->host_old_termios);
    }
    if (pipe(bridge->wake_pipe) < 0) {
        perror("pipe");
        return false;
    }
    if (pthread_create(&bridge->thread, NULL, serial_pty_bridge_thread, bridge) != 0) {
        perror("pthread_create");
        return false;
    }
    bridge->thread_started = true;
    return true;
}

static void stop_serial_pty_bridge(struct serial_pty_bridge *bridge)
{
    if (bridge->wake_pipe[1] >= 0) {
        (void)write(bridge->wake_pipe[1], "x", 1);
    }
    if (bridge->thread_started) {
        (void)pthread_join(bridge->thread, NULL);
    }
    if (bridge->host_raw_enabled) {
        (void)tcsetattr(STDIN_FILENO, TCSANOW, &bridge->host_old_termios);
    }
    if (bridge->wake_pipe[0] >= 0) {
        close(bridge->wake_pipe[0]);
    }
    if (bridge->wake_pipe[1] >= 0) {
        close(bridge->wake_pipe[1]);
    }
    if (bridge->slave_fd >= 0) {
        close(bridge->slave_fd);
    }
    if (bridge->master_fd >= 0) {
        close(bridge->master_fd);
    }
}

int main(int argc, char *const argv[])
{
    struct cmdline cmdline;
    if (!parse_cmdline(argc, argv, &cmdline)) {
        print_help(argv[0]);
        return 1;
    }
    if (cmdline.show_help) {
        print_help(argv[0]);
        return 0;
    }

    int err = krun_set_log_level(KRUN_LOG_LEVEL_ERROR);
    if (err) {
        return report_error("krun_set_log_level", err);
    }

    int ctx_id = krun_create_ctx();
    if (ctx_id < 0) {
        return report_error("krun_create_ctx", ctx_id);
    }

    if ((err = krun_set_vm_config(ctx_id, cmdline.num_vcpus, cmdline.ram_mib))) {
        return report_error("krun_set_vm_config", err);
    }

    if (cmdline.control_socket != NULL) {
        /* --memory-mib is the resize ceiling; the balloon starts inflated so
         * the guest's usable RAM equals --balloon-initial-mib (defaulting to
         * the full ceiling if unset). */
        uint32_t initial_mib = cmdline.balloon_initial_mib != 0 ? cmdline.balloon_initial_mib
                                                                : cmdline.ram_mib;
        if ((err = krun_set_balloon(ctx_id, initial_mib, cmdline.balloon_min_mib,
                                    cmdline.control_socket))) {
            return report_error("krun_set_balloon", err);
        }
    }
    if ((err = krun_set_os_mode(ctx_id))) {
        return report_error("krun_set_os_mode", err);
    }
    char *owned_kernel_cmdline = NULL;
    const char *kernel_cmdline = effective_kernel_cmdline(&cmdline, &owned_kernel_cmdline);
    if (cmdline.poweroff_after_ready && kernel_cmdline == NULL) {
        fprintf(stderr, "Failed to allocate kernel command line\n");
        return 1;
    }
    if ((err = krun_set_kernel(ctx_id, cmdline.kernel_path, cmdline.kernel_format,
                               cmdline.initramfs_path, kernel_cmdline))) {
        free(owned_kernel_cmdline);
        return report_error("krun_set_kernel", err);
    }
    free(owned_kernel_cmdline);
    if (cmdline.guest_init != NULL) {
        if ((err = krun_set_os_init(ctx_id, cmdline.guest_init))) {
            return report_error("krun_set_os_init", err);
        }
    }
    if ((err = krun_add_disk3(ctx_id, "root", cmdline.root_disk, KRUN_DISK_FORMAT_RAW,
                              false, false, cmdline.disk_sync_mode))) {
        return report_error("krun_add_disk3", err);
    }
    if ((err = krun_set_os_root(ctx_id, cmdline.root_device, cmdline.root_fstype,
                                cmdline.root_options))) {
        return report_error("krun_set_os_root", err);
    }
    if ((err = krun_set_kernel_console(ctx_id, cmdline.console))) {
        return report_error("krun_set_kernel_console", err);
    }

    for (size_t i = 0; i < cmdline.virtiofs_mount_count; i++) {
        /* krun_add_virtiofs3 with shm_size=0 is equivalent to krun_add_virtiofs;
         * a non-zero --virtiofs-dax-size opens a DAX window so guests map shared
         * read-only files straight from the host page cache. */
        err = krun_add_virtiofs3(ctx_id, cmdline.virtiofs_mounts[i].tag,
                                 cmdline.virtiofs_mounts[i].path,
                                 cmdline.virtiofs_dax_size,
                                 cmdline.virtiofs_mounts[i].read_only);
        if (err) {
            return report_error("krun_add_virtiofs3", err);
        }
    }

    if (cmdline.passt_socket != NULL) {
        uint8_t mac[] = {0x5a, 0x94, 0xef, 0xe4, 0x0c, 0xee};
        err = krun_add_net_unixstream(ctx_id, cmdline.passt_socket, -1, mac,
                                      cmdline.net_features, 0);
        if (err) {
            return report_error("krun_add_net_unixstream", err);
        }
    }
    if (cmdline.gvproxy_socket != NULL) {
        uint8_t mac[] = {0x5a, 0x94, 0xef, 0xe4, 0x0c, 0xee};
        uint32_t flags = cmdline.gvproxy_vfkit_magic ? NET_FLAG_VFKIT : 0;
        err = krun_add_net_unixgram(ctx_id, cmdline.gvproxy_socket, -1, mac,
                                    cmdline.net_features, flags);
        if (err) {
            return report_error("krun_add_net_unixgram", err);
        }
    }

    struct serial_pty_bridge bridge;
    memset(&bridge, 0, sizeof(bridge));
    int serial_input_fd = STDIN_FILENO;
    int serial_output_fd = STDOUT_FILENO;
    if (cmdline.serial_pty) {
        if (!setup_serial_pty_bridge(&bridge)) {
            return 1;
        }
        serial_input_fd = bridge.slave_fd;
        serial_output_fd = bridge.slave_fd;
    }

    if ((err = krun_add_serial_console_default(ctx_id, serial_input_fd, serial_output_fd))) {
        if (cmdline.serial_pty) {
            stop_serial_pty_bridge(&bridge);
        }
        return report_error("krun_add_serial_console_default", err);
    }

    err = krun_start_enter(ctx_id);
    if (cmdline.serial_pty) {
        stop_serial_pty_bridge(&bridge);
    }
    if (err) {
        return report_error("krun_start_enter", err);
    }

    return 0;
}
#endif
