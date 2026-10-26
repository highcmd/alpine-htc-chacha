/*
 * chacha-idle - switch the LCD, keyboard and touch-key backlights off after a
 * period without key presses or touches, and back on at the next one.
 * Replaces console blanking, which on msm_fb only clears the picture (the
 * driver has no fb_blank) and leaves every backlight lit.
 *
 * Power key: a short press switches the screen off (or on), holding it for
 * LONG_PRESS seconds runs "poweroff".
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
#include <time.h>
#include <unistd.h>
#include <dirent.h>
#include <linux/input.h>

#define MAXDEV		4
#define LEDS		"/sys/class/leds/"
#define LONG_PRESS	3000	/* ms */
#define CONSOLE		"/dev/tty1"

/* the sensors (light, proximity, compass) report continuously, so only these wake */
static const char *wake_names[] = { "chacha-keypad", "cy8c-touchscreen" };
static const char *leds[] = { "lcd-backlight", "keyboard-backlight", "button-backlight" };
#define NLEDS	(sizeof(leds) / sizeof(leds[0]))

static struct pollfd pfd[MAXDEV];
static int npfd, dark, saved[NLEDS];
static long long power_down;	/* ms timestamp of the power key press, 0 = up */
static int power_woke;		/* this press woke the screen: its release does nothing */
static volatile sig_atomic_t quit;

static void on_signal(int sig)
{
	(void)sig;
	quit = 1;
}

static long long now_ms(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1000LL + ts.tv_nsec / 1000000;
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

static void open_inputs(void)
{
	char path[64], name[64];
	struct dirent *de;
	DIR *d = opendir("/dev/input");
	int fd;
	unsigned i;

	if (!d)
		return;
	while ((de = readdir(d)) && npfd < MAXDEV) {
		if (strncmp(de->d_name, "event", 5))
			continue;
		snprintf(path, sizeof(path), "/dev/input/%s", de->d_name);
		fd = open(path, O_RDONLY | O_NONBLOCK);
		if (fd < 0)
			continue;
		if (ioctl(fd, EVIOCGNAME(sizeof(name)), name) >= 0)
			for (i = 0; i < sizeof(wake_names) / sizeof(wake_names[0]); i++)
				if (!strcmp(name, wake_names[i])) {
					pfd[npfd].fd = fd;
					pfd[npfd++].events = POLLIN;
					fd = -1;
					break;
				}
		if (fd >= 0)
			close(fd);
	}
	closedir(d);
}

static void grab(int on)
{
	int i;

	for (i = 0; i < npfd; i++)
		ioctl(pfd[i].fd, EVIOCGRAB, on);
}

static void go_dark(void)
{
	unsigned l;

	for (l = 0; l < NLEDS; l++) {
		saved[l] = led_get(leds[l]);
		led_set(leds[l], 0);
	}
	grab(1);
	dark = 1;
}

static void restore_lights(void)
{
	unsigned l;

	for (l = 0; l < NLEDS; l++)
		if (saved[l] >= 0)
			led_set(leds[l], saved[l]);
}

/* Read all pending events and track the power key. Returns 1 if a key or touch
 * other than power arrived; *power_press / *power_short report a power press
 * and a short press-release seen in this batch. */
static int read_events(int *power_press, int *power_short)
{
	struct input_event ev[16];
	int i, n, k, other = 0;

	for (i = 0; i < npfd; i++)
		while ((n = read(pfd[i].fd, ev, sizeof(ev))) > 0)
			for (k = 0; k < n / (int)sizeof(ev[0]); k++) {
				if (ev[k].type == EV_KEY && ev[k].code == KEY_POWER) {
					if (ev[k].value == 1 && !power_down) {
						power_down = now_ms();
						power_woke = dark;
						*power_press = 1;
					} else if (ev[k].value == 0 && power_down) {
						if (!power_woke)
							*power_short = 1;
						power_down = 0;
					}
				} else if (ev[k].type != EV_SYN)
					other = 1;
			}
	return other;
}

static void wake(void)
{
	int dummy1 = 0, dummy2 = 0;

	/* release the grab only once the waking key/touch is over; the console may
	 * then see a stray key release, which is harmless */
	usleep(300000);
	read_events(&dummy1, &dummy2);
	grab(0);
	restore_lights();
	dark = 0;
}

static void power_off(void)
{
	int fd;

	if (dark) {
		grab(0);
		restore_lights();
		dark = 0;
	}
	fd = open(CONSOLE, O_WRONLY | O_NOCTTY);
	if (fd >= 0) {
		const char msg[] = "\r\n\033[1;33m*** Powering off ***\033[0m\r\n";
		if (write(fd, msg, sizeof(msg) - 1) < 0)
			perror(CONSOLE);
		close(fd);
	}
	execl("/sbin/poweroff", "poweroff", (char *)NULL);
	perror("poweroff");
	exit(1);
}

int main(int argc, char **argv)
{
	struct sigaction sa = { .sa_handler = on_signal };
	long long last = now_ms(), t, wait;
	int timeout = 300, r, power_press, power_short, other;

	if (argc == 3 && !strcmp(argv[1], "-t"))
		timeout = atoi(argv[2]);
	else if (argc != 1) {
		fprintf(stderr, "usage: %s [-t SECONDS]\n", argv[0]);
		return 2;
	}
	open_inputs();
	if (!npfd) {
		fprintf(stderr, "no keypad/touchscreen input devices\n");
		return 1;
	}

	/* no SA_RESTART: poll() returns EINTR, the loop ends and the lights come back */
	sigaction(SIGTERM, &sa, NULL);
	sigaction(SIGINT, &sa, NULL);

	while (!quit) {
		/* sleep until the idle deadline or the long-press deadline */
		t = now_ms();
		wait = 0x7fffffff;
		if (!dark && timeout > 0 && last + timeout * 1000LL - t < wait)
			wait = last + timeout * 1000LL - t;
		if (power_down && power_down + LONG_PRESS - t < wait)
			wait = power_down + LONG_PRESS - t;
		if (wait < 0)
			wait = 0;

		r = poll(pfd, npfd, wait == 0x7fffffff ? -1 : (int)wait);
		if (r < 0) {
			if (errno == EINTR)
				break;
			perror("poll");
			return 1;
		}
		t = now_ms();
		power_press = power_short = 0;
		other = r > 0 ? read_events(&power_press, &power_short) : 0;

		if (power_down && t - power_down >= LONG_PRESS)
			power_off();

		if (dark) {
			if (other || power_press)
				wake();
			last = t;
		} else if (power_short) {
			go_dark();
		} else if (r > 0) {
			last = t;
		} else if (timeout > 0 && t - last >= timeout * 1000LL) {
			go_dark();
		}
	}
	if (dark)
		restore_lights();
	return 0;
}
