/*
 * wlpriv - send an Android-style private string command to the bcm4329
 * wext driver via SIOCSIWPRIV, e.g. "COUNTRY PL", "SCAN-ACTIVE", "RSSI".
 *
 * usage: wlpriv <ifname> <command...>
 */
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <linux/wireless.h>

int main(int argc, char **argv)
{
	char buf[256];
	struct iwreq wrq;
	int fd, i;

	if (argc < 3) {
		fprintf(stderr, "usage: %s <ifname> <command...>\n", argv[0]);
		return 2;
	}
	buf[0] = '\0';
	for (i = 2; i < argc; i++) {
		if (i > 2)
			strncat(buf, " ", sizeof(buf) - strlen(buf) - 1);
		strncat(buf, argv[i], sizeof(buf) - strlen(buf) - 1);
	}

	fd = socket(AF_INET, SOCK_DGRAM, 0);
	if (fd < 0) {
		perror("socket");
		return 1;
	}
	memset(&wrq, 0, sizeof(wrq));
	strncpy(wrq.ifr_name, argv[1], IFNAMSIZ - 1);
	wrq.u.data.pointer = buf;
	wrq.u.data.length = sizeof(buf);	/* driver replies in the same buffer */
	if (ioctl(fd, SIOCSIWPRIV, &wrq) < 0) {
		perror("SIOCSIWPRIV");
		close(fd);
		return 1;
	}
	buf[sizeof(buf) - 1] = '\0';
	printf("%s\n", buf);
	close(fd);
	return 0;
}
