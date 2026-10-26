/*
 * chacha-idle - switch the LCD, keyboard and touch-key backlights off after a
 * period without key presses or touches, and back on at the next one.
 * Replaces console blanking, which on msm_fb only clears the picture (the
 * driver has no fb_blank) and leaves every backlight lit.
 *
 * usage: chacha-idle [-t SECONDS]   (default 300; 0 = never)
 *
 * While dark the keypad and touchscreen are grabbed, so the key or touch that
 * wakes the screen is not typed into the console.
 */
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <linux/input.h>

#define MAXDEV	4
#define LEDS	"/sys/class/leds/"

/* the sensors (light, proximity, compass) report continuously, so only these wake */
static const char *wake_names[] = { "chacha-keypad", "cy8c-touchscreen" };
static const char *leds[] = { "lcd-backlight", "keyboard-backlight", "button-backlight" };
#define NLEDS	(sizeof(leds) / sizeof(leds[0]))

static int saved[NLEDS];
static volatile sig_atomic_t quit;

static void on_signal(int sig)
{
	(void)sig;
	quit = 1;
}

static int led_get(const char *name)
{
	char path[64], buf[16] = "";
	int fd, n;

	snprintf(path, sizeof(path), LEDS "%s/brightness", name);
	fd = open(path, O_RDONLY);
	if (fd < 0)
		return -1;
	n = read(fd, buf, sizeof(buf) - 1);
	close(fd);
	return n > 0 ? atoi(buf) : -1;
}

static void led_set(const char *name, int value)
{
	char path[64], buf[16];
	int fd, n;

	snprintf(path, sizeof(path), LEDS "%s/brightness", name);
	fd = open(path, O_WRONLY);
	if (fd < 0)
		return;
	n = snprintf(buf, sizeof(buf), "%d\n", value);
	if (write(fd, buf, n) < 0)
		perror(path);
	close(fd);
}

static int open_inputs(struct pollfd *pfd)
{
	char path[64], name[64];
	struct dirent *de;
	DIR *d = opendir("/dev/input");
	int n = 0, fd;
	unsigned i;

	if (!d)
		return 0;
	while ((de = readdir(d)) && n < MAXDEV) {
		if (strncmp(de->d_name, "event", 5))
			continue;
		snprintf(path, sizeof(path), "/dev/input/%s", de->d_name);
		fd = open(path, O_RDONLY);
		if (fd < 0)
			continue;
		if (ioctl(fd, EVIOCGNAME(sizeof(name)), name) >= 0)
			for (i = 0; i < sizeof(wake_names) / sizeof(wake_names[0]); i++)
				if (!strcmp(name, wake_names[i])) {
					pfd[n].fd = fd;
					pfd[n++].events = POLLIN;
					fd = -1;
					break;
				}
		if (fd >= 0)
			close(fd);
	}
	closedir(d);
	return n;
}

static void grab(struct pollfd *pfd, int n, int on)
{
	int i;

	for (i = 0; i < n; i++)
		ioctl(pfd[i].fd, EVIOCGRAB, on);
}

int main(int argc, char **argv)
{
	struct pollfd pfd[MAXDEV];
	struct input_event ev[16];
	struct sigaction sa = { .sa_handler = on_signal };
	int timeout = 300, n, i, r, dark = 0;
	unsigned l;

	if (argc == 3 && !strcmp(argv[1], "-t"))
		timeout = atoi(argv[2]);
	else if (argc != 1) {
		fprintf(stderr, "usage: %s [-t SECONDS]\n", argv[0]);
		return 2;
	}
	n = open_inputs(pfd);
	if (!n) {
		fprintf(stderr, "no keypad/touchscreen input devices\n");
		return 1;
	}

	/* no SA_RESTART: poll() returns EINTR, the loop ends and the lights come back */
	sigaction(SIGTERM, &sa, NULL);
	sigaction(SIGINT, &sa, NULL);

	while (!quit) {
		r = poll(pfd, n, dark || timeout <= 0 ? -1 : timeout * 1000);
		if (r < 0) {
			if (errno == EINTR)
				break;
			perror("poll");
			return 1;
		}
		if (r == 0) {
			for (l = 0; l < NLEDS; l++) {
				saved[l] = led_get(leds[l]);
				led_set(leds[l], 0);
			}
			grab(pfd, n, 1);
			dark = 1;
			continue;
		}
		for (i = 0; i < n; i++)
			if (pfd[i].revents & POLLIN)
				if (read(pfd[i].fd, ev, sizeof(ev)) < 0 && errno != EAGAIN)
					perror("read");
		if (dark) {
			/* release only after the waking key/touch is over: with the grab gone
			 * the console would see a stray key release, which is harmless */
			usleep(300000);
			for (i = 0; i < n; i++)
				while (poll(&pfd[i], 1, 0) > 0 && read(pfd[i].fd, ev, sizeof(ev)) > 0)
					;
			grab(pfd, n, 0);
			for (l = 0; l < NLEDS; l++)
				if (saved[l] >= 0)
					led_set(leds[l], saved[l]);
			dark = 0;
		}
	}
	if (dark)
		for (l = 0; l < NLEDS; l++)
			if (saved[l] >= 0)
				led_set(leds[l], saved[l]);
	return 0;
}
