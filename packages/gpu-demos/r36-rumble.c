/*
 * r36-rumble.c - drive the R36 Max 2 vibration motor through the normal force
 * feedback path, so the rumble GPIO can be tested the same way an application
 * would use it.  Compiled on the device, where <linux/input.h> supplies the real
 * struct ff_effect for this kernel - hand-assembling that struct from Python is
 * fragile because its union contains pointers (the kernel here wants 48 bytes).
 *
 *   cc -O2 -o r36-rumble r36-rumble.c
 *   ./r36-rumble /dev/input/event2 800      # 800 ms of full-strength rumble
 *
 * While it runs it samples the "rumble" line out of /sys/kernel/debug/gpio so
 * the pin level and what you feel are recorded together.
 */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <linux/input.h>

static void nap_ms(long ms)
{
	struct timespec ts = { .tv_sec = ms / 1000, .tv_nsec = (ms % 1000) * 1000000L };
	nanosleep(&ts, NULL);
}

/* the level the gpiod core currently shows for the rumble line, "hi"/"lo" */
static const char *pin_level(char *buf, size_t len)
{
	FILE *f = fopen("/sys/kernel/debug/gpio", "re");
	static char out[8];
	char line[256];

	strcpy(out, "n/a");
	if (!f)
		return snprintf(buf, len, "%s", out), "no debugfs";
	while (fgets(line, sizeof(line), f)) {
		char *p = strstr(line, "|rumble");
		if (!p)
			continue;
		p = strstr(p, "out");
		if (p && (p[4] == 'h' || p[4] == 'l')) {
			out[0] = p[4];
			out[1] = 0;
			strcpy(out, p[4] == 'h' ? "hi" : "lo");
		}
		break;
	}
	fclose(f);
	return snprintf(buf, len, "%s", out), buf;
}

int main(int argc, char **argv)
{
	const char *node = argc > 1 ? argv[1]
		: "/dev/input/by-path/platform-rocknix-singleadc-joypad-event-joystick";
	int ms = argc > 2 ? atoi(argv[2]) : 800;
	int fd, id, rc;
	char buf[32];
	struct ff_effect eff;
	struct input_event ev;

	fd = open(node, O_RDWR);
	if (fd < 0) {
		fprintf(stderr, "open %s: %s\n", node, strerror(errno));
		return 1;
	}
	printf("node        : %s\n", node);
	printf("ff_effect   : %zu bytes on this kernel\n", sizeof(eff));
	printf("pin before  : rumble=%s\n", pin_level(buf, sizeof(buf)));

	memset(&eff, 0, sizeof(eff));
	eff.type = FF_RUMBLE;
	eff.id = -1;
	eff.u.rumble.strong_magnitude = 0xffff;
	eff.u.rumble.weak_magnitude = 0x8000;
	eff.replay.length = ms;

	rc = ioctl(fd, EVIOCSFF, &eff);
	if (rc < 0) {
		fprintf(stderr, "EVIOCSFF: %s\n", strerror(errno));
		fprintf(stderr, "  (the driver has to set FF_RUMBLE in its ffbit)\n");
		close(fd);
		return 1;
	}
	id = eff.id;
	printf("effect id   : %d (strong=0xffff weak=0x8000, replay %d ms)\n", id, ms);

	memset(&ev, 0, sizeof(ev));
	ev.type = EV_FF;
	ev.code = id;
	ev.value = 1;
	if (write(fd, &ev, sizeof(ev)) < 0)
		fprintf(stderr, "play: %s\n", strerror(errno));
	else
		printf("playing     : %d ms - you should feel it\n", ms);

	for (int i = 0; i * 60 < ms + 300; i++) {
		pin_level(buf, sizeof(buf));
		printf("  t+%4d ms  rumble=%s\n", i * 60, buf);
		nap_ms(60);
	}

	ev.value = 0;
	if (write(fd, &ev, sizeof(ev)) < 0)
		fprintf(stderr, "stop: %s\n", strerror(errno));
	nap_ms(120);
	printf("pin after   : rumble=%s\n", pin_level(buf, sizeof(buf)));
	ioctl(fd, EVIOCRMFF, id);
	close(fd);
	return 0;
}
