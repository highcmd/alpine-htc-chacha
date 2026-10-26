/*
 * reboot-bootloader - reboot with a restart command string, like Android's
 * "reboot bootloader": HTC HBOOT then stays in fastboot mode.
 *
 * usage: reboot-bootloader [command]   (default "bootloader")
 */
#include <stdio.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <linux/reboot.h>

int main(int argc, char **argv)
{
	const char *cmd = argc > 1 ? argv[1] : "bootloader";

	sync();
	syscall(SYS_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2,
		LINUX_REBOOT_CMD_RESTART2, cmd);
	perror("reboot");
	return 1;
}
