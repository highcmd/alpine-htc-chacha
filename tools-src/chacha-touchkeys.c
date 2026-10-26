/*
 * chacha-touchkeys - turn the four capacitive keys below the HTC ChaCha LCD
 * (part of the cy8c touchscreen, multitouch protocol A) into key presses via
 * uinput. Touches on the LCD area itself are ignored.
 *
 * usage: chacha-touchkeys [-d] [-y YMIN] SPEC1 SPEC2 SPEC3 SPEC4
 *   SPECn: keys for the n-th touch key from the left (Home, Menu, Back,
 *          Search), "+"-separated Linux keycodes, e.g. "183+48" (SYM/Ctrl+B).
 *   -y YMIN: raw Y at which the key strip starts (default 700)
 *   -d: debug, print raw touches
 */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <linux/input.h>
#include <linux/uinput.h>

#define NKEYS		4
#define MAXCOMBO	4
#define X_MIN		17
#define X_MAX		1007

static int combo[NKEYS][MAXCOMBO], ncombo[NKEYS];
static int ufd, debug, ymin = 700;

static int open_touchscreen(void)
{
	char path[64], name[64];
	struct dirent *de;
	DIR *d = opendir("/dev/input");
	int fd;

	if (!d)
		return -1;
	while ((de = readdir(d))) {
		if (strncmp(de->d_name, "event", 5))
			continue;
		snprintf(path, sizeof(path), "/dev/input/%s", de->d_name);
		fd = open(path, O_RDONLY);
		if (fd < 0)
			continue;
		if (ioctl(fd, EVIOCGNAME(sizeof(name)), name) >= 0 &&
		    strstr(name, "cy8c-touchscreen")) {
			closedir(d);
			return fd;
		}
		close(fd);
	}
	closedir(d);
	return -1;
}

static void emit(int type, int code, int value)
{
	struct input_event ev;

	memset(&ev, 0, sizeof(ev));
	ev.type = type;
	ev.code = code;
	ev.value = value;
	if (write(ufd, &ev, sizeof(ev)) < 0)
		perror("uinput write");
}

static void press(int k, int down)
{
	int i;

	if (down) {
		for (i = 0; i < ncombo[k]; i++)
			emit(EV_KEY, combo[k][i], 1);
	} else {
		for (i = ncombo[k] - 1; i >= 0; i--)
			emit(EV_KEY, combo[k][i], 0);
	}
	emit(EV_SYN, SYN_REPORT, 0);
}

static int setup_uinput(void)
{
	struct uinput_user_dev dev;
	int k, i;

	ufd = open("/dev/uinput", O_WRONLY);
	if (ufd < 0)
		ufd = open("/dev/input/uinput", O_WRONLY);
	if (ufd < 0)
		return -1;
	ioctl(ufd, UI_SET_EVBIT, EV_KEY);
	ioctl(ufd, UI_SET_EVBIT, EV_SYN);
	for (k = 0; k < NKEYS; k++)
		for (i = 0; i < ncombo[k]; i++)
			ioctl(ufd, UI_SET_KEYBIT, combo[k][i]);
	memset(&dev, 0, sizeof(dev));
	snprintf(dev.name, UINPUT_MAX_NAME_SIZE, "chacha-touchkeys");
	dev.id.bustype = BUS_VIRTUAL;
	if (write(ufd, &dev, sizeof(dev)) != sizeof(dev))
		return -1;
	return ioctl(ufd, UI_DEV_CREATE);
}

int main(int argc, char **argv)
{
	struct input_event ev;
	int tfd, opt, k, x = -1, y = -1, pressure = 0;
	int hit = -1, cur = -1;

	while ((opt = getopt(argc, argv, "dy:")) != -1) {
		if (opt == 'd')
			debug = 1;
		else if (opt == 'y')
			ymin = atoi(optarg);
		else
			return 2;
	}
	if (argc - optind != NKEYS) {
		fprintf(stderr, "usage: %s [-d] [-y YMIN] SPEC1 SPEC2 SPEC3 SPEC4\n", argv[0]);
		return 2;
	}
	for (k = 0; k < NKEYS; k++) {
		char *s = strdup(argv[optind + k]), *tok;

		for (tok = strtok(s, "+"); tok && ncombo[k] < MAXCOMBO; tok = strtok(NULL, "+"))
			combo[k][ncombo[k]++] = atoi(tok);
		free(s);
	}

	tfd = open_touchscreen();
	if (tfd < 0) {
		fprintf(stderr, "cy8c-touchscreen not found\n");
		return 1;
	}
	if (setup_uinput() < 0) {
		perror("uinput");
		return 1;
	}

	while (read(tfd, &ev, sizeof(ev)) == sizeof(ev)) {
		if (ev.type == EV_ABS) {
			if (ev.code == ABS_MT_POSITION_X)
				x = ev.value;
			else if (ev.code == ABS_MT_POSITION_Y)
				y = ev.value;
			else if (ev.code == ABS_MT_TOUCH_MAJOR || ev.code == ABS_MT_PRESSURE)
				pressure = ev.value;
		} else if (ev.type == EV_SYN && ev.code == SYN_MT_REPORT) {
			/* one contact finished: is it on the key strip? */
			if (pressure > 0 && y >= ymin && x >= 0 && hit < 0) {
				k = (x - X_MIN) * NKEYS / (X_MAX - X_MIN + 1);
				hit = k < 0 ? 0 : k >= NKEYS ? NKEYS - 1 : k;
			}
			if (debug && pressure > 0)
				fprintf(stderr, "touch x=%d y=%d p=%d\n", x, y, pressure);
			x = y = -1;
			pressure = 0;
		} else if (ev.type == EV_SYN && ev.code == SYN_REPORT) {
			if (hit != cur) {
				if (cur >= 0)
					press(cur, 0);
				if (hit >= 0)
					press(hit, 1);
				if (debug)
					fprintf(stderr, "key %d -> %d\n", cur, hit);
				cur = hit;
			}
			hit = -1;
		}
	}
	perror("read");
	return 1;
}
