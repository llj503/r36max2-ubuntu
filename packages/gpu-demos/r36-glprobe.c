/* r36-glprobe.c - does this stack offer a *desktop* OpenGL context?
 *
 * EmulationStation (the Aloshi/cehughes/batocera/es-de lineages) renders with
 * desktop GL, not GLES.  On RK3326 the only 3D driver is panfrost/Mesa and what
 * Mesa exposes depends on the GPU generation, so this must be measured, not
 * assumed.  Prints EGL_CLIENT_APIS, then really creates each kind of context over
 * GBM and reads back GL_VERSION / GL_RENDERER.
 *
 * build: cc -O2 -Wall r36-glprobe.c $(pkg-config --cflags --libs egl gbm libdrm)
 */
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <gbm.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>

#ifndef EGL_PLATFORM_GBM_MESA
#define EGL_PLATFORM_GBM_MESA 0x31D7
#endif
#ifndef EGL_OPENGL_ES3_BIT
#define EGL_OPENGL_ES3_BIT 0x0040
#endif
#ifndef EGL_OPENGL_BIT
#define EGL_OPENGL_BIT 0x0008        /* EGL 1.5 RENDERABLE_TYPE bit */
#endif
#define GL_VERSION  0x1F02
#define GL_RENDERER 0x1F01

typedef const char *(*glstr_t)(unsigned);

static void try_api(EGLDisplay d, struct gbm_device *gbm, EGLint api,
                    EGLint rendertype, const char *name)
{
    if (!eglBindAPI(api)) {
        printf("  %-9s eglBindAPI refused (0x%x) - Mesa does not offer this API\n",
               name, eglGetError());
        return;
    }
    /* No ALPHA_SIZE constraint on purpose: the panel format here is XRGB8888 and
     * asking for 8 alpha bits makes eglChooseConfig come back empty, which is how
     * the first version of this probe reported "no config" for a GPU that is fine. */
    EGLint attrs[] = {
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
        EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8,
        EGL_DEPTH_SIZE, 16,
        EGL_RENDERABLE_TYPE, rendertype,
        EGL_NONE
    };
    EGLConfig cfg; EGLint n = 0;
    if (!eglChooseConfig(d, attrs, &cfg, 1, &n) || n < 1) {
        printf("  %-9s no WINDOW config for this renderable (err=0x%x)\n", name, eglGetError());
        return;
    }
    EGLint vis = 0, rgba[4] = {0, 0, 0, 0}, dep = 0;
    eglGetConfigAttrib(d, cfg, EGL_NATIVE_VISUAL_ID, &vis);
    eglGetConfigAttrib(d, cfg, EGL_DEPTH_SIZE, &dep);
    eglGetConfigAttrib(d, cfg, EGL_RED_SIZE, &rgba[0]);
    eglGetConfigAttrib(d, cfg, EGL_GREEN_SIZE, &rgba[1]);
    eglGetConfigAttrib(d, cfg, EGL_BLUE_SIZE, &rgba[2]);
    eglGetConfigAttrib(d, cfg, EGL_ALPHA_SIZE, &rgba[3]);
    EGLContext c = eglCreateContext(d, cfg, EGL_NO_CONTEXT, NULL);
    if (!c) {
        printf("  %-9s eglCreateContext FAILED (0x%x)\n", name, eglGetError());
        return;
    }
    struct gbm_surface *s = gbm_surface_create(gbm, 640, 480, (uint32_t)vis,
                                              GBM_BO_USE_RENDERING);
    EGLSurface surf = s ? eglCreateWindowSurface(d, cfg, (EGLNativeWindowType)s, NULL) : NULL;
    int cur = (surf && eglMakeCurrent(d, surf, surf, c)) ? 1 : 0;
    printf("  %-9s config(rgba %d/%d/%d/%d depth %d vis 0x%x) window=%s current=%s\n",
           name, rgba[0], rgba[1], rgba[2], rgba[3], dep, vis,
           surf ? "ok" : "fail", cur ? "YES" : "no");
    if (cur) {
        glstr_t gs = (glstr_t)(void *)eglGetProcAddress("glGetString");
        if (gs)
            printf("            GL_VERSION  = %s\n            GL_RENDERER = %s\n",
                   gs(GL_VERSION), gs(GL_RENDERER));
        /* and prove the pipeline works end to end, not just "context exists" */
        EGLBoolean sw = eglSwapBuffers(d, surf);
        printf("            eglSwapBuffers = %s (0x%x)\n", sw ? "ok" : "FAIL", eglGetError());
        eglMakeCurrent(d, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    }
    if (surf) eglDestroySurface(d, surf);
    eglDestroyContext(d, c);
    if (s) gbm_surface_destroy(s);
    eglBindAPI(EGL_OPENGL_ES_API);
}

int main(void)
{
    int fd = open("/dev/dri/card0", O_RDWR | O_CLOEXEC);
    if (fd < 0) { perror("open card0"); return 1; }
    struct gbm_device *gbm = gbm_create_device(fd);
    PFNEGLGETPLATFORMDISPLAYEXTPROC gpd =
        (PFNEGLGETPLATFORMDISPLAYEXTPROC)(void *)eglGetProcAddress("eglGetPlatformDisplayEXT");
    EGLDisplay d = gpd ? gpd(EGL_PLATFORM_GBM_MESA, gbm, NULL)
                       : eglGetDisplay((EGLNativeDisplayType)gbm);
    EGLint maj, mi;
    if (d == EGL_NO_DISPLAY || !eglInitialize(d, &maj, &mi)) {
        printf("  !! no EGL display on GBM (0x%x)\n", eglGetError());
        return 1;
    }
    printf("  egl %d.%d vendor=%s\n", maj, mi, eglQueryString(d, EGL_VENDOR));
    printf("  EGL_CLIENT_APIS = %s\n", eglQueryString(d, EGL_CLIENT_APIS));
    printf("=== can a context actually be made? ===\n");
    try_api(d, gbm, EGL_OPENGL_ES_API, EGL_OPENGL_ES2_BIT | EGL_OPENGL_ES3_BIT, "GLES2/3");
    try_api(d, gbm, EGL_OPENGL_ES_API, EGL_OPENGL_ES3_BIT, "GLES3");
    try_api(d, gbm, EGL_OPENGL_API, EGL_OPENGL_BIT, "desktop-GL");

    /* ROCKNIX builds EmulationStation with -DGLES3=1 on exactly this class of
     * hardware, so a bare "no" from the first attempt would be worth chasing:
     * enumerate every ES3-renderable WINDOW config and try each one, because the
     * first config in the list can be a 10-bit one that no surface matches. */
    printf("\n=== every ES3-renderable WINDOW config, tried individually ===\n");
    EGLint n = 0;
    eglGetConfigs(d, NULL, 0, &n);
    EGLConfig *cs = calloc(n > 0 ? n : 1, sizeof *cs);
    eglGetConfigs(d, cs, n, &n);
    int shown = 0;
    for (int i = 0; i < n && shown < 6; i++) {
        EGLint rt = 0, st = 0, r = 0, g = 0, b = 0, a = 0, id = 0, vis = 0;
        eglGetConfigAttrib(d, cs[i], EGL_RENDERABLE_TYPE, &rt);
        eglGetConfigAttrib(d, cs[i], EGL_SURFACE_TYPE, &st);
        if (!(rt & EGL_OPENGL_ES3_BIT) || !(st & EGL_WINDOW_BIT)) continue;
        eglGetConfigAttrib(d, cs[i], EGL_RED_SIZE, &r);
        eglGetConfigAttrib(d, cs[i], EGL_GREEN_SIZE, &g);
        eglGetConfigAttrib(d, cs[i], EGL_BLUE_SIZE, &b);
        eglGetConfigAttrib(d, cs[i], EGL_ALPHA_SIZE, &a);
        eglGetConfigAttrib(d, cs[i], EGL_CONFIG_ID, &id);
        eglGetConfigAttrib(d, cs[i], EGL_NATIVE_VISUAL_ID, &vis);
        shown++;
        eglBindAPI(EGL_OPENGL_ES_API);
        EGLint atts[] = { EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE };
        EGLContext c = eglCreateContext(d, cs[i], EGL_NO_CONTEXT, atts);
        struct gbm_surface *s = gbm_surface_create(gbm, 320, 240, (uint32_t)vis, GBM_BO_USE_RENDERING);
        EGLSurface sf = s ? eglCreateWindowSurface(d, cs[i], (EGLNativeWindowType)s, NULL) : NULL;
        int cur = (c && sf && eglMakeCurrent(d, sf, sf, c)) ? 1 : 0;
        const char *ver = "-";
        if (cur) {
            glstr_t gs = (glstr_t)(void *)eglGetProcAddress("glGetString");
            if (gs) ver = gs(GL_VERSION);
            eglMakeCurrent(d, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        }
        printf("  cfg %-3d rgba %d/%d/%d/%d vis 0x%x ctx=%s win=%s  %s\n",
               id, r, g, b, a, vis, c ? "ok" : "FAIL", sf ? "ok" : "fail", ver);
        if (sf) eglDestroySurface(d, sf);
        if (c) eglDestroyContext(d, c);
        if (s) gbm_surface_destroy(s);
    }
    if (!shown) printf("  (no ES3-renderable WINDOW configs at all)\n");
    free(cs);
    eglTerminate(d);
    gbm_device_destroy(gbm);
    close(fd);
    return 0;
}
