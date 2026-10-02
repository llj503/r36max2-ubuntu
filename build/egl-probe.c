/* egl-probe.c - enumerate what Mesa/panfrost actually offers on the GBM
 * platform, then try to build a real window surface for every WINDOW-capable
 * config so the EGL_BAD_MATCH is pinned to a specific (config, gbm format)
 * pair instead of being guessed at.
 * build: gcc -O2 egl-probe.c $(pkg-config --cflags --libs gbm egl libdrm) -ldrm
 */
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <gbm.h>
#include <drm.h>
#include <drm_mode.h>
#include <xf86drm.h>
#include <xf86drmMode.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* Some distro EGL headers omit the Mesa-specific tokens; the values are ABI
 * constants and safe to define by hand. */
#ifndef EGL_PLATFORM_GBM_MESA
#define EGL_PLATFORM_GBM_MESA 0x31D7
#endif
#ifndef EGL_NO_CONFIG_MESA
#define EGL_NO_CONFIG_MESA ((EGLConfig)0)
#endif
#ifndef EGL_OPENGL_ES3_BIT
#define EGL_OPENGL_ES3_BIT 0x0040
#endif
#ifndef EGL_CONTEXT_CLIENT_VERSION
#define EGL_CONTEXT_CLIENT_VERSION 0x3098
#endif

static const char *sname(unsigned t)
{
    static char b[64];
    b[0] = 0;
    if (t & EGL_WINDOW_BIT) strcat(b, "W");
    if (t & EGL_PIXMAP_BIT) strcat(b, "PM");
    if (t & EGL_PBUFFER_BIT) strcat(b, "PB");
    if (t & EGL_SWAP_BEHAVIOR_PRESERVED_BIT) strcat(b, "+S");
    if (!*b) strcpy(b, "(none)");
    return b;
}

static unsigned natvis(EGLDisplay d, EGLConfig c)
{
    EGLint v = -1;
    eglGetConfigAttrib(d, c, EGL_NATIVE_VISUAL_ID, &v);
    return (unsigned)v;
}

int main(int argc, char **argv)
{
    const char *card = argc > 1 ? argv[1] : "/dev/dri/card0";
    EGLint es2_attr[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
    int fd = open(card, O_RDWR | O_CLOEXEC);
    if (fd < 0) { perror("open card"); return 1; }

    struct gbm_device *gbm = gbm_create_device(fd);
    if (!gbm) { fprintf(stderr, "gbm_create_device failed\n"); return 1; }

    PFNEGLGETPLATFORMDISPLAYEXTPROC gpd =
        (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplayEXT");
    EGLDisplay d = gpd ? gpd(EGL_PLATFORM_GBM_MESA, gbm, NULL) : EGL_NO_DISPLAY;
    EGLint maj = 0, mi = 0;
    if (d == EGL_NO_DISPLAY || !eglInitialize(d, &maj, &mi)) {
        d = eglGetDisplay((EGLNativeDisplayType)gbm);
        if (d == EGL_NO_DISPLAY || !eglInitialize(d, &maj, &mi)) {
            fprintf(stderr, "no EGL display (0x%x)\n", eglGetError());
            return 1;
        }
        printf("display via eglGetDisplay\n");
    } else {
        printf("display via EGL_PLATFORM_GBM_MESA, egl %d.%d\n", maj, mi);
    }
    printf("client APIs  : %s\n", eglQueryString(d, EGL_CLIENT_APIS));

    EGLint n = 0;
    if (!eglGetConfigs(d, NULL, 0, &n)) { fprintf(stderr, "eglGetConfigs 0x%x\n", eglGetError()); return 1; }
    EGLConfig *cs = calloc(n > 0 ? n : 1, sizeof *cs);
    eglGetConfigs(d, cs, n, &n);
    printf("configs      : %d total\n\n", n);
    printf("%-4s %-9s %-8s %-12s %-6s %-6s %-9s %-6s %s\n",
           "id", "vis", "surface", "r/g/b", "alpha", "depth", "rendbk", "buf", "caveat");
    for (int i = 0; i < n; i++) {
        EGLint id = -1, r = -1, g = -1, b = -1, a = -1, dep = -1, st = 0, buf = -1, cv = 0, rt = 0;
        eglGetConfigAttrib(d, cs[i], EGL_CONFIG_ID, &id);
        eglGetConfigAttrib(d, cs[i], EGL_SURFACE_TYPE, &st);
        eglGetConfigAttrib(d, cs[i], EGL_RENDERABLE_TYPE, &rt);
        eglGetConfigAttrib(d, cs[i], EGL_RED_SIZE, &r);
        eglGetConfigAttrib(d, cs[i], EGL_GREEN_SIZE, &g);
        eglGetConfigAttrib(d, cs[i], EGL_BLUE_SIZE, &b);
        eglGetConfigAttrib(d, cs[i], EGL_ALPHA_SIZE, &a);
        eglGetConfigAttrib(d, cs[i], EGL_DEPTH_SIZE, &dep);
        eglGetConfigAttrib(d, cs[i], EGL_BUFFER_SIZE, &buf);
        eglGetConfigAttrib(d, cs[i], EGL_CONFIG_CAVEAT, &cv);
        char rb[16];
        snprintf(rb, sizeof rb, "%d/%d/%d", r, g, b);
        printf("%-4d 0x%-7x %-8s %-12s %-6d %-6d %-9s %-6d 0x%x\n",
               id, natvis(d, cs[i]), sname((unsigned)st), rb, a, dep,
               rt == EGL_OPENGL_ES2_BIT ? "ES2"
                 : rt == EGL_OPENGL_ES3_BIT ? "ES3"
                 : rt == (EGL_OPENGL_ES2_BIT | EGL_OPENGL_ES3_BIT) ? "ES2+ES3"
                 : rt == EGL_OPENGL_BIT ? "GL" : "other",
               buf, cv);
    }

    /* what does ChooseConfig actually answer for the masks we care about? */
    struct { const char *name; EGLint attr[16]; } tests[] = {
        { "W+ES2",        { EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_NONE } },
        { "W+PB+ES2",     { EGL_SURFACE_TYPE, EGL_WINDOW_BIT | EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_NONE } },
        { "W+rgb888+ES2", { EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_NONE } },
        { "PB+ES2",       { EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_NONE } },
        { "bare ES2",     { EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_NONE } },
    };
    printf("\n--- eglChooseConfig probes ---\n");
    for (unsigned t = 0; t < sizeof tests / sizeof *tests; t++) {
        EGLConfig out[8]; EGLint got = 0;
        EGLBoolean ok = eglChooseConfig(d, tests[t].attr, out, 8, &got);
        printf("%-14s ok=%d n=%-2d err=0x%x  ids:", tests[t].name, ok == EGL_TRUE, got, eglGetError());
        for (int i = 0; i < got; i++) {
            EGLint id = -1, st = 0;
            eglGetConfigAttrib(d, out[i], EGL_CONFIG_ID, &id);
            eglGetConfigAttrib(d, out[i], EGL_SURFACE_TYPE, &st);
            printf(" %d(%s)", id, sname((unsigned)st));
        }
        printf("\n");
    }

    /* the real question: can a window surface be made, per config? */
    printf("\n--- gbm_surface + eglCreateWindowSurface per WINDOW config ---\n");
    for (int i = 0; i < n; i++) {
        EGLint st = 0, id = -1;
        eglGetConfigAttrib(d, cs[i], EGL_SURFACE_TYPE, &st);
        eglGetConfigAttrib(d, cs[i], EGL_CONFIG_ID, &id);
        if (!(st & EGL_WINDOW_BIT)) continue;
        unsigned vis = natvis(d, cs[i]);
        struct gbm_surface *s = gbm_surface_create(gbm, 1024, 768, vis,
                                                   GBM_BO_USE_RENDERING | GBM_BO_USE_SCANOUT);
        if (!s) {
            printf("cfg %-3d vis 0x%-8x gbm_surface_create FAILED\n", id, vis);
            continue;
        }
        EGLContext c = eglCreateContext(d, cs[i], EGL_NO_CONTEXT,
                                        es2_attr);
        EGLint cerr = eglGetError();
        EGLSurface ws = eglCreateWindowSurface(d, cs[i], (EGLNativeWindowType)s, NULL);
        EGLint serr = eglGetError();
        int cur = 0;
        if (c && ws)
            cur = eglMakeCurrent(d, ws, ws, c);
        printf("cfg %-3d vis 0x%-8x ctx=%s(0x%x) win=%s(0x%x) makecurrent=%d  renderer=%s\n",
               id, vis, c ? "ok" : "FAIL", cerr, ws ? "ok" : "FAIL", serr, cur,
               cur ? (const char *)glGetString(GL_RENDERER) : "-");
        if (ws) eglDestroySurface(d, ws);
        if (c) eglDestroyContext(d, c);
        gbm_surface_destroy(s);
    }

    /* context with no config at all, using EGL_KHR_no_config_context */
    printf("\n--- EGL_KHR_no_config_context path ---\n");
    if (strstr(eglQueryString(d, EGL_EXTENSIONS), "EGL_KHR_no_config_context")) {
        struct gbm_surface *s = gbm_surface_create(gbm, 1024, 768, GBM_FORMAT_XRGB8888,
                                                   GBM_BO_USE_RENDERING | GBM_BO_USE_SCANOUT);
        EGLContext c = eglCreateContext(d, EGL_NO_CONFIG_MESA, EGL_NO_CONTEXT,
                                        es2_attr);
        EGLint cerr = eglGetError();
        EGLSurface ws = eglCreateWindowSurface(d, EGL_NO_CONFIG_MESA,
                                               (EGLNativeWindowType)s, NULL);
        printf("ctx=%s(0x%x) win=%s(0x%x)\n", c ? "ok" : "FAIL", cerr,
               ws ? "ok" : "FAIL", eglGetError());
        if (c && ws && eglMakeCurrent(d, ws, ws, c))
            printf("renderer     : %s\n", glGetString(GL_RENDERER));
        if (ws) eglDestroySurface(d, ws);
        if (c) eglDestroyContext(d, c);
        gbm_surface_destroy(s);
    }

    eglTerminate(d);
    gbm_device_destroy(gbm);
    close(fd);
    return 0;
}
