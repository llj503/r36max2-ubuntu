/* r36-sdlprobe.c - one video driver per process, because SDL bootstraps the video
 * device once: after a failed SDL_Init(SDL_INIT_VIDEO) a second attempt with a
 * different SDL_VIDEODRIVER in the same process reports the *first* driver's error,
 * which is exactly how an earlier version of this probe told us "wayland not
 * available" on a box that had a live weston session.
 *
 *   r36-sdlprobe kmsdrm      # needs: no compositor holding DRM master
 *   r36-sdlprobe wayland     # needs: WAYLAND_DISPLAY + XDG_RUNTIME_DIR in env
 *
 * It also reports whether the card could be opened and whether DRM master was
 * obtained, because "kmsdrm not available" is what SDL says for all of: another
 * master, no CRTC, or a VT it cannot take over.
 *
 * build: cc -O2 -Wall r36-sdlprobe.c $(sdl2-config --cflags --libs) -ldrm
 */
#include <SDL2/SDL.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <xf86drm.h>
#include <xf86drmMode.h>     /* drmModeResPtr / drmModeGetResources live here, not in xf86drm.h */

static void drm_report(void)
{
    int fd = open("/dev/dri/card0", O_RDWR | O_CLOEXEC);
    if (fd < 0) { printf("    card0: cannot open (%s)\n", strerror(errno)); return; }
    drmVersionPtr v = drmGetVersion(fd);
    printf("    card0: opened, driver=%s\n", v && v->name ? v->name : "?");
    if (v) drmFreeVersion(v);
    int m = drmIsMaster(fd);
    printf("    drmIsMaster now: %d\n", m);
    int s = drmSetMaster(fd);
    printf("    drmSetMaster: %s%s\n", s == 0 ? "GRANTED (nobody else holds it)" : "refused",
           s == 0 ? "" : "  <-- a compositor owns the card");
    if (s == 0) drmDropMaster(fd);
    /* what modes are there at all */
    drmModeResPtr res = drmModeGetResources(fd);
    if (res) {
        printf("    resources: %d connectors, %d crtcs\n", res->count_connectors, res->count_crtcs);
        drmModeFreeResources(res);
    }
    close(fd);
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "usage: %s <driver>   (kmsdrm|wayland|x11|dummy)\n", argv[0]);
        return 2;
    }
    const char *drv = argv[1];
    printf("  driver=%s  WAYLAND_DISPLAY=%s XDG_RUNTIME_DIR=%s VT=%s\n", drv,
           getenv("WAYLAND_DISPLAY") ? getenv("WAYLAND_DISPLAY") : "(unset)",
           getenv("XDG_RUNTIME_DIR") ? getenv("XDG_RUNTIME_DIR") : "(unset)",
           getenv("XDG_VTNR") ? getenv("XDG_VTNR") : "(unset)");
    if (strcmp(drv, "kmsdrm") == 0) drm_report();

    setenv("SDL_VIDEODRIVER", drv, 1);
    unsetenv("SDL_VIDEO_DRIVER");
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS) != 0) {
        printf("  RESULT: SDL_Init failed: %s\n", SDL_GetError());
        SDL_Quit();
        return 1;
    }
    printf("  SDL picked: %s\n", SDL_GetCurrentVideoDriver());
    SDL_DisplayMode dm;
    if (SDL_GetDesktopDisplayMode(0, &dm) == 0)
        printf("  display 0: %dx%d fmt=%s refresh=%dHz\n", dm.w, dm.h,
               SDL_GetPixelFormatName(dm.format), dm.refresh_rate);
    SDL_Window *w = SDL_CreateWindow("probe", 0, 0, 0, 0, SDL_WINDOW_FULLSCREEN);
    if (!w) {
        printf("  RESULT: no window: %s\n", SDL_GetError());
        SDL_Quit();
        return 1;
    }
    int ww = 0, wh = 0;
    SDL_GetWindowSize(w, &ww, &wh);
    SDL_GLContext gl = SDL_GL_CreateContext(w);
    if (gl) {
        /* no GL headers on the include path here - resolve the symbol through SDL,
           which is also what proves the driver really loaded */
        typedef const unsigned char *(*glGetString_t)(unsigned);
        glGetString_t gs = (glGetString_t)(void *)SDL_GL_GetProcAddress("glGetString");
        const char *ver = "-", *ren = "-";
        if (gs) { ver = (const char *)gs(0x1F02 /*GL_VERSION*/); ren = (const char *)gs(0x1F01 /*GL_RENDERER*/); }
        /* SDL2 returns void from SDL_GL_SwapWindow - detect failure the supported
           way instead of assigning an int to a non-existent return value */
        SDL_GL_SwapWindow(w);
        SDL_GL_SetSwapInterval(1);
        int si = SDL_GL_GetSwapInterval();   /* SDL2: no out-parameter (that is SDL3) */
        printf("  RESULT: WINDOW OK %dx%d  GL: version=%s renderer=%s  swap done, swapinterval=%d (%s)\n",
               ww, wh, ver, ren, si, SDL_GetError()[0] ? SDL_GetError() : "no error");
        SDL_GL_DeleteContext(gl);
    } else {
        printf("  RESULT: WINDOW OK %dx%d  but SDL_GL_CreateContext failed: %s\n",
               ww, wh, SDL_GetError());
    }
    SDL_DestroyWindow(w);
    SDL_Quit();
    return 0;
}
