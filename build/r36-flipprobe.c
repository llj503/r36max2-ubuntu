/*
 * r36-flipprobe.c - ask the kernel directly whether page-flip completion
 * interrupts still arrive on this VOP/DSI pipeline.
 *
 * The weston investigation left two explanations standing: "weston had been
 * running a long time" versus "weston was SIGKILLed while a flip was in flight
 * and the vsync completion got lost".  Through weston they look identical, so
 * measure underneath it: take DRM master, flip between two framebuffers N times,
 * and time every completion event.  A healthy 60 Hz pipeline answers in ~16 ms;
 * a lost interrupt shows up as poll timeouts, which is exactly what makes
 * drm_atomic_helper_wait_for_vblanks() WARN after ~41 s and leaves the panel
 * frozen on the last frame.
 *
 * Build on the device:
 *   cc -O2 -o /usr/local/bin/r36-flipprobe /usr/local/src/r36-flipprobe.c \
 *      $(pkg-config --cflags --libs libdrm)
 *
 * Usage: r36-flipprobe [flips] [gap-ms]     exit 0 = every flip completed
 */
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <xf86drm.h>
#include <xf86drmMode.h>
#include <drm.h>

static double now_ms(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

/* libdrm calls this for each flip completion event */
static void flip_done(int fd, unsigned int seq, unsigned int tv_sec,
		      unsigned int tv_usec, void *user_data)
{
	(void)fd; (void)seq; (void)tv_sec; (void)tv_usec;
	*(double *)user_data = now_ms();
}

struct buf {
	uint32_t handle, pitch, fb_id, size;
	void *map;
};

static int make_buf(int fd, uint32_t w, uint32_t h, uint32_t rgb, struct buf *out)
{
	struct drm_mode_create_dumb cd;
	struct drm_mode_map_dumb md;
	uint32_t *pix;
	size_t i;

	memset(out, 0, sizeof(*out));
	memset(&cd, 0, sizeof(cd));
	cd.width = w;
	cd.height = h;
	cd.bpp = 32;
	if (drmIoctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &cd)) {
		fprintf(stderr, "  create dumb: %s\n", strerror(errno));
		return -1;
	}
	out->handle = cd.handle;
	out->pitch = cd.pitch;
	out->size = (uint32_t)cd.size;

	memset(&md, 0, sizeof(md));
	md.handle = cd.handle;
	if (drmIoctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &md)) {
		fprintf(stderr, "  map dumb: %s\n", strerror(errno));
		return -1;
	}
	out->map = mmap(0, out->size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, md.offset);
	if (out->map == MAP_FAILED) {
		fprintf(stderr, "  mmap: %s\n", strerror(errno));
		return -1;
	}
	for (pix = out->map, i = 0; i < out->size / 4; i++)
		pix[i] = 0xff000000u | rgb;
	if (drmModeAddFB(fd, w, h, 24, 32, out->pitch, out->handle, &out->fb_id)) {
		fprintf(stderr, "  addfb: %s\n", strerror(errno));
		return -1;
	}
	return 0;
}

int main(int argc, char **argv)
{
	const char *node = "/dev/dri/card0";
	int flips = argc > 1 ? atoi(argv[1]) : 60;
	int gap_ms = argc > 2 ? atoi(argv[2]) : 15;
	int fd, i, crtc_id = -1;
	uint32_t conn_id = 0;
	drmModeRes *res;
	drmModeConnector *conn = NULL;
	drmModeCrtc *crtc = NULL;
	struct buf a, b;
	double lat_sum = 0.0, lat_max = 0.0;
	int ok = 0, timed_out = 0, rc = 0;

	if (flips < 1)
		flips = 1;
	fd = open(node, O_RDWR | O_CLOEXEC);
	if (fd < 0) {
		perror("open /dev/dri/card0");
		return 2;
	}
	if (drmSetMaster(fd)) {
		fprintf(stderr, "  drmSetMaster failed: %s"
			" - is a compositor still holding the card?\n", strerror(errno));
		return 2;
	}
	res = drmModeGetResources(fd);
	if (!res) {
		fprintf(stderr, "  drmModeGetResources failed\n");
		return 2;
	}
	for (i = 0; i < res->count_connectors; i++) {
		drmModeConnector *c = drmModeGetConnector(fd, res->connectors[i]);

		if (c && c->connection == DRM_MODE_CONNECTED && c->count_modes > 0) {
			conn = c;
			conn_id = c->connector_id;
			break;
		}
		if (c)
			drmModeFreeConnector(c);
	}
	if (!conn || res->count_crtcs < 1) {
		fprintf(stderr, "  no connected connector or crtc\n");
		return 2;
	}
	/* the crtc driving this connector, not blindly crtcs[0] */
	if (conn->encoder_id) {
		drmModeEncoder *enc = drmModeGetEncoder(fd, conn->encoder_id);

		if (enc) {
			crtc_id = enc->crtc_id;
			drmModeFreeEncoder(enc);
		}
	}
	if (crtc_id < 0)
		crtc_id = res->crtcs[0];
	crtc = drmModeGetCrtc(fd, crtc_id);
	if (!crtc || !crtc->mode_valid || !crtc->mode.hdisplay) {
		fprintf(stderr, "  crtc %d has no active mode (console blanked off?)\n", crtc_id);
		return 2;
	}
	printf("  probe: connector id %d, crtc %d, mode %dx%d@%.1f clock %d kHz, %d flips, gap %d ms\n",
	       conn_id, crtc_id, crtc->mode.hdisplay, crtc->mode.vdisplay,
	       crtc->mode.clock ? 1000.0 * crtc->mode.clock /
			(crtc->mode.htotal * crtc->mode.vtotal) : 0.0,
	       crtc->mode.clock, flips, gap_ms);

	if (make_buf(fd, crtc->mode.hdisplay, crtc->mode.vdisplay, 0x102030, &a) ||
	    make_buf(fd, crtc->mode.hdisplay, crtc->mode.vdisplay, 0xe0c040, &b)) {
		fprintf(stderr, "  could not build probe framebuffers\n");
		return 2;
	}
	if (drmModeSetCrtc(fd, crtc_id, a.fb_id, 0, 0, &conn_id, 1, &crtc->mode)) {
		fprintf(stderr, "  SetCrtc failed: %s\n", strerror(errno));
		return 2;
	}

	for (i = 0; i < flips; i++) {
		struct pollfd pfd = { .fd = fd, .events = POLLIN };
		drmEventContext ev;
		uint32_t fb = (i & 1) ? b.fb_id : a.fb_id;
		double t0 = now_ms(), done = -1.0;

		memset(&ev, 0, sizeof(ev));
		ev.version = DRM_EVENT_CONTEXT_VERSION;
		ev.page_flip_handler = flip_done;

		if (drmModePageFlip(fd, crtc_id, fb, DRM_MODE_PAGE_FLIP_EVENT, &done)) {
			fprintf(stderr, "  flip %d: submit failed: %s\n", i, strerror(errno));
			timed_out++;
			break;
		}
		while (now_ms() - t0 < 3000.0) {
			int pr = poll(&pfd, 1, 100);

			if (pr > 0) {
				drmHandleEvent(fd, &ev);
				if (done > 0)
					break;
				continue;
			}
			if (pr < 0 && errno != EINTR)
				break;
		}
		if (done < 0) {
			printf("  flip %3d: NO COMPLETION EVENT within 3000 ms  <-- stalled pipeline\n", i);
			timed_out++;
			break;
		}
		{
			double lat = done - t0;

			ok++;
			lat_sum += lat;
			if (lat > lat_max)
				lat_max = lat;
			if (i < 3 || i % 15 == 0 || lat > 100.0)
				printf("  flip %3d: %.1f ms%s\n", i, lat, lat > 100.0 ? "  (slow)" : "");
		}
		if (gap_ms)
			usleep((unsigned)gap_ms * 1000);
	}

	printf("  ---- %d/%d flips completed, timeouts=%d, avg %.1f ms, max %.1f ms ----\n",
	       ok, flips, timed_out, ok ? lat_sum / ok : 0.0, lat_max);

	/*
	 * No manual "put the console's framebuffer back": this libdrm's
	 * drmModeCrtc does not even expose fb_id, and it is not needed - dropping
	 * master makes the DRM core run its lastclose path, which restores the
	 * fbdev emulation console the same way it does when any compositor exits.
	 */
	drmModeRmFB(fd, a.fb_id);
	drmModeRmFB(fd, b.fb_id);
	if (drmDropMaster(fd))
		fprintf(stderr, "  drmDropMaster failed: %s\n", strerror(errno));
	close(fd);

	rc = timed_out ? 3 : 0;
	printf("  verdict: %s\n", rc ? "PIPELINE STALLED (flip completions are not arriving)"
				     : "flip completions healthy");
	return rc;
}
