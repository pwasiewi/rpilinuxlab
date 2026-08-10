/* usermode-helper.c — the single binary the kernel is allowed to exec.
 *
 * CONFIG_STATIC_USERMODEHELPER (hardened.fragment) points every kernel
 * usermode-helper call — request_module() for fs/netfilter/crypto
 * autoloading, the core_pattern pipe, orderly_poweroff() — at this fixed
 * path, compiled into the kernel as read-only data. The program the kernel
 * actually wanted arrives as argv[0]; exec it only if it is on the audited
 * list. This keeps the mitigation honest: overwriting modprobe_path (the
 * classic post-exploit trick the option exists to kill) now buys an
 * attacker a choice among the entries below instead of arbitrary code.
 *
 * Installed by cmd_live_kernel whenever the final .config carries the
 * option. A kernel with the option and no helper has NO module autoloading
 * at all, which surfaces as absurdities like mount's "unknown filesystem
 * type 'binfmt_misc'" and iptables' "Table does not exist" — how this file
 * came to exist (installed nvhard host, 2026-08-10). Rejected and failed
 * execs are reported to /dev/kmsg so dmesg shows them.
 *
 * Not needed in the initramfs: genkernel's early userspace modprobes its
 * LUKS/btrfs modules explicitly and never relies on kernel-side autoload.
 */
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static const char *const allow[] = {
    "/sbin/modprobe",                    /* request_module() */
    "/usr/sbin/modprobe",
    "/usr/lib/systemd/systemd-coredump", /* kernel.core_pattern pipe */
    "/lib/systemd/systemd-coredump",
    "/sbin/poweroff",                    /* orderly_poweroff(): thermal emergency */
    "/sbin/reboot",                      /* orderly_reboot() */
    "/sbin/request-key",                 /* key management upcall (keyutils) */
    NULL
};

int main(int argc, char **argv)
{
    if (argc >= 1 && argv[0] != NULL)
        for (const char *const *p = allow; *p != NULL; p++)
            if (strcmp(argv[0], *p) == 0) {
                execv(*p, argv);
                break; /* whitelisted but exec failed — report below */
            }

    int fd = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
    if (fd >= 0) {
        char msg[192];
        int n = snprintf(msg, sizeof(msg), "usermode-helper: refused %.128s\n",
                         (argc >= 1 && argv[0] != NULL) ? argv[0] : "(no argv[0])");
        if (n > 0) {
            ssize_t w = write(fd, msg, (size_t)n);
            (void)w;
        }
        close(fd);
    }
    return 1;
}
