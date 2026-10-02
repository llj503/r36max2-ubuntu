/* r36-gles2-demo.c - head-less EGL/GLES2 on GBM+DRM for the R36 Max 2 panel.
 *
 * Takes DRM master on /dev/dri/card0, modesets the DSI connector, renders an
 * animated shader through Mesa's panfrost driver, and reports the achieved
 * frame rate.  Used to prove the GPU stack end to end (kernel driver + Mesa +
 * GBM scanout), which glmark2 cannot do here because the Ubuntu build has no
 * GBM/DRM backend.
 *
 * build: gcc r36-gles2-demo.c -o r36-gles2-demo $(pkg-config --cflags --libs gbm egl glesv2) -ldrm
 */
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <drm.h>
#include <errno.h>
#include <fcntl.h>
#include <gbm.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <unistd.h>
#include <xf86drm.h>
#include <xf86drmMode.h>

#ifndef EGL_PLATFORM_GBM_MESA
#define EGL_PLATFORM_GBM_MESA 0x31D7
#endif
#ifndef EGL_NO_CONFIG_MESA
#define EGL_NO_CONFIG_MESA ((EGLConfig)0)
#endif

static const char *VERT =
    "attribute vec2 a_pos;\n"
    "void main(void) { gl_Position = vec4(a_pos, 0.0, 1.0); }\n";

static const char *FRAG =
    "precision highp float;\n"
    "uniform float u_time;\n"
    "uniform vec2 u_res;\n"
    "void main(void) {\n"
    "  vec2 uv = gl_FragCoord.xy / u_res;\n"
    "  vec2 c = (uv - 0.5) * vec2(u_res.x / u_res.y, 1.0);\n"
    "  float r = length(c);\n"
    "  float a = atan(c.y, c.x);\n"
    "  float spin = a + u_time * 0.8 + sin(r * 6.0 - u_time * 2.0) * 0.6;\n"
    "  float bands = 0.5 + 0.5 * sin(spin * 9.0);\n"
    "  vec3 col = mix(vec3(0.05, 0.25, 0.55), vec3(0.95, 0.55, 0.10), bands);\n"
    "  col = mix(col, vec3(0.98, 0.95, 0.85), smoothstep(0.75, 0.0, r));\n"
    "  float grid = step(0.97, fract(uv.x * 16.0)) + step(0.97, fract(uv.y * 12.0));\n"
    "  col += 0.25 * grid;\n"
    "  gl_FragColor = vec4(col, 1.0);\n"
    "}\n";

/* deliberately ALU-heavy: 48-iteration Mandelbrot per pixel, used by the
 * R36_FBO bench mode to measure raw shader/fill throughput without the
 * display pipeline serialising the result */
static const char *FRAG_HEAVY =
    "precision highp float;\n"
    "uniform float u_time;\n"
    "uniform vec2 u_res;\n"
    "void main(void) {\n"
    "  vec2 uv = gl_FragCoord.xy / u_res;\n"
    "  vec2 p = (uv - 0.5) * vec2(3.2, 2.4) + vec2(u_time * 0.05, 0.0);\n"
    "  vec2 z = vec2(0.0);\n"
    "  float i = 0.0;\n"
    "  for (int n = 0; n < 48; n++) {\n"
    "    z = vec2(z.x*z.x - z.y*z.y, 2.0*z.x*z.y) + p;\n"
    "    if (dot(z, z) > 4.0) break;\n"
    "    i += 1.0;\n"
    "  }\n"
    "  float t = i / 48.0;\n"
    "  gl_FragColor = vec4(fract(t * 5.0), 1.0 - t, 0.3 + 0.7 * t, 1.0);\n"
    "}\n";

static double now_s(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

static GLuint shader(GLenum type, const char *src)
{
    GLuint s = glCreateShader(type);
    glShaderSource(s, 1, &src, NULL);
    glCompileShader(s);
    GLint ok = 0;
    glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[1024];
        glGetShaderInfoLog(s, sizeof log, NULL, log);
        fprintf(stderr, "shader compile failed: %s\n", log);
        exit(1);
    }
    return s;
}

int main(int argc, char **argv)
{
    const char *card = argc > 1 ? argv[1] : "/dev/dri/card0";
    double seconds = argc > 2 ? atof(argv[2]) : 5.0;
    int offscreen = 0;
    int fd = open(card, O_RDWR | O_CLOEXEC);
    if (fd < 0) { perror("open card"); return 1; }

    drmVersionPtr ver = drmGetVersion(fd);
    printf("drm driver   : %s\n", ver->name);
    drmFreeVersion(ver);

    drmModeResPtr res = drmModeGetResources(fd);
    if (!res) { fprintf(stderr, "no resources (not a KMS node?)\n"); return 1; }
    drmModeConnectorPtr conn = NULL;
    for (int i = 0; i < res->count_connectors && !conn; i++) {
        drmModeConnectorPtr c = drmModeGetConnector(fd, res->connectors[i]);
        if (c && c->connection == DRM_MODE_CONNECTED && c->count_modes > 0)
            conn = c;
        else if (c)
            drmModeFreeConnector(c);
    }
    if (!conn) { fprintf(stderr, "no connected connector with modes\n"); return 1; }
    drmModeModeInfoPtr mode = &conn->modes[0];
    printf("connector    : id %u  mode %dx%d@%dHz\n",
           conn->connector_type_id, mode->hdisplay, mode->vdisplay, mode->vrefresh);

    drmModeEncoderPtr enc = drmModeGetEncoder(fd, conn->encoder_id);
    uint32_t crtc_id = 0;
    if (enc) {
        crtc_id = enc->crtc_id;
        drmModeFreeEncoder(enc);
    }
    if (!crtc_id && res->count_crtcs)
        crtc_id = res->crtcs[0];

    /* remember what the console was scanning out so we can hand the panel back
     * instead of leaving the CRTC pointing at a freed GBM buffer */
    uint32_t orig_fb = 0, orig_x = 0, orig_y = 0;
    drmModeCrtcPtr pcrtc = drmModeGetCrtc(fd, crtc_id);
    if (pcrtc) {
        orig_fb = pcrtc->buffer_id;
        orig_x = pcrtc->x;
        orig_y = pcrtc->y;
        drmModeFreeCrtc(pcrtc);
    }
    printf("crtc         : id %u  console fb %u\n", crtc_id, orig_fb);

    struct gbm_device *gbm = gbm_create_device(fd);
    if (!gbm) { fprintf(stderr, "gbm_create_device failed\n"); return 1; }

    /* One display for the whole program: an EGLConfig is only valid on the
     * display that produced it, so re-initialising a second display after
     * eglChooseConfig() made the config invalid (EGL 0x3001). */
    EGLDisplay dpy = EGL_NO_DISPLAY;
    EGLint maj = 0, mi = 0;
    PFNEGLGETPLATFORMDISPLAYEXTPROC get_platform_display =
        (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplayEXT");
    if (get_platform_display) {
        dpy = get_platform_display(EGL_PLATFORM_GBM_MESA, gbm, NULL);
        if (dpy != EGL_NO_DISPLAY && eglInitialize(dpy, &maj, &mi))
            printf("egl          : via EGL_PLATFORM_GBM_MESA\n");
        else
            dpy = EGL_NO_DISPLAY;
    }
    if (dpy == EGL_NO_DISPLAY) {
        dpy = eglGetDisplay((EGLNativeDisplayType)gbm);
        if (dpy == EGL_NO_DISPLAY || !eglInitialize(dpy, &maj, &mi)) {
            fprintf(stderr, "eglInitialize failed (0x%x)\n", eglGetError());
            return 1;
        }
        printf("egl          : via eglGetDisplay(gbm)\n");
    }
    eglBindAPI(EGL_OPENGL_ES_API);
    EGLint ctx_attr[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };

    /* Mesa's GBM platform advertises WINDOW configs only (a PBUFFER request
     * returns 0 configs here) and eglCreateWindowSurface() matches the config
     * against the gbm_surface's fourcc, so the surface must be created from
     * the chosen config's EGL_NATIVE_VISUAL_ID - not from a hardcoded
     * XRGB8888, which is what produced EGL_BAD_MATCH (0x3009). */
    EGLint cand[][14] = {
        { EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8,
          EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 0, EGL_BUFFER_SIZE, 24,
          EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT },
        { EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8,
          EGL_BLUE_SIZE, 8, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_NONE,
          EGL_NONE, EGL_NONE, EGL_NONE },
        { EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
          EGL_NONE, EGL_NONE, EGL_NONE, EGL_NONE, EGL_NONE, EGL_NONE, EGL_NONE,
          EGL_NONE, EGL_NONE, EGL_NONE },
        { EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_NONE, EGL_NONE, EGL_NONE,
          EGL_NONE, EGL_NONE, EGL_NONE, EGL_NONE, EGL_NONE, EGL_NONE, EGL_NONE,
          EGL_NONE, EGL_NONE },
    };
    EGLContext ctx = EGL_NO_CONTEXT;
    EGLSurface egl_surf = EGL_NO_SURFACE;
    EGLConfig cfg = NULL;
    struct gbm_surface *surf = NULL;

    for (unsigned ci = 0; ci < sizeof cand / sizeof *cand && egl_surf == EGL_NO_SURFACE; ci++) {
        EGLConfig c = NULL; EGLint n = 0, id = -1, vis = 0;
        if (!eglChooseConfig(dpy, cand[ci], &c, 1, &n) || n < 1) {
            printf("  cfg cand %u: none (0x%x)\n", ci, eglGetError());
            continue;
        }
        eglGetConfigAttrib(dpy, c, EGL_CONFIG_ID, &id);
        eglGetConfigAttrib(dpy, c, EGL_NATIVE_VISUAL_ID, &vis);
        struct gbm_surface *s = gbm_surface_create(
            gbm, mode->hdisplay, mode->vdisplay, (uint32_t)vis,
            GBM_BO_USE_SCANOUT | GBM_BO_USE_RENDERING);
        uint32_t use = GBM_BO_USE_SCANOUT | GBM_BO_USE_RENDERING;
        if (!s) {
            use = GBM_BO_USE_RENDERING;
            s = gbm_surface_create(gbm, mode->hdisplay, mode->vdisplay,
                                   (uint32_t)vis, use);
        }
        if (!s) { printf("  cfg cand %u: cfg %d vis 0x%x gbm_surface_create failed\n",
                         ci, id, vis); continue; }
        EGLContext cx = eglCreateContext(dpy, c, EGL_NO_CONTEXT, ctx_attr);
        EGLSurface ws = cx == EGL_NO_CONTEXT ? EGL_NO_SURFACE
            : eglCreateWindowSurface(dpy, c, (EGLNativeWindowType)s, NULL);
        EGLint err = eglGetError();
        int made = cx != EGL_NO_CONTEXT && ws != EGL_NO_SURFACE &&
                   eglMakeCurrent(dpy, ws, ws, cx);
        printf("  cfg cand %u: cfg %d vis 0x%x use 0x%x ctx=%s win=%s(0x%x) current=%d\n",
               ci, id, vis, use, cx ? "ok" : "FAIL", ws ? "ok" : "FAIL", err, made);
        if (made) { cfg = c; ctx = cx; egl_surf = ws; surf = s; break; }
        if (ws != EGL_NO_SURFACE) eglDestroySurface(dpy, ws);
        if (cx != EGL_NO_CONTEXT) eglDestroyContext(dpy, cx);
        gbm_surface_destroy(s);
    }

    if (egl_surf == EGL_NO_SURFACE &&
        strstr(eglQueryString(dpy, EGL_EXTENSIONS), "EGL_KHR_no_config_context")) {
        printf("falling back to EGL_KHR_no_config_context\n");
        surf = gbm_surface_create(gbm, mode->hdisplay, mode->vdisplay,
                                  GBM_FORMAT_XRGB8888,
                                  GBM_BO_USE_SCANOUT | GBM_BO_USE_RENDERING);
        ctx = eglCreateContext(dpy, EGL_NO_CONFIG_MESA, EGL_NO_CONTEXT, ctx_attr);
        egl_surf = ctx != EGL_NO_CONTEXT && surf
            ? eglCreateWindowSurface(dpy, EGL_NO_CONFIG_MESA,
                                     (EGLNativeWindowType)surf, NULL)
            : EGL_NO_SURFACE;
        if (egl_surf != EGL_NO_SURFACE && !eglMakeCurrent(dpy, egl_surf, egl_surf, ctx))
            egl_surf = EGL_NO_SURFACE;
    }
    if (egl_surf == EGL_NO_SURFACE) {
        fprintf(stderr, "no GL context: %s\n", eglGetError() ? "egl error" : "surface failed");
        return 1;
    }
    eglSwapInterval(dpy, 0);

    EGLint cid = -1, cdepth = -1, cbuf = -1, cvis = 0;
    if (cfg) {
        eglGetConfigAttrib(dpy, cfg, EGL_CONFIG_ID, &cid);
        eglGetConfigAttrib(dpy, cfg, EGL_DEPTH_SIZE, &cdepth);
        eglGetConfigAttrib(dpy, cfg, EGL_BUFFER_SIZE, &cbuf);
        eglGetConfigAttrib(dpy, cfg, EGL_NATIVE_VISUAL_ID, &cvis);
    }
    printf("EGL config   : id %d  buf %d  depth %d  fourcc 0x%x (%c%c%c%c)\n",
           cid, cbuf, cdepth, (unsigned)cvis,
           cvis & 255, (cvis >> 8) & 255, (cvis >> 16) & 255, (cvis >> 24) & 255);
    printf("GL vendor    : %s\n", glGetString(GL_VENDOR));
    printf("GL renderer  : %s\n", glGetString(GL_RENDERER));
    printf("GL version   : %s\n", glGetString(GL_VERSION));
    printf("EGL version  : %s / api %d.%d\n", eglQueryString(dpy, EGL_VERSION), maj, mi);

    GLuint prog = glCreateProgram();
    glAttachShader(prog, shader(GL_VERTEX_SHADER, VERT));
    glAttachShader(prog, shader(GL_FRAGMENT_SHADER, FRAG));
    glBindAttribLocation(prog, 0, "a_pos");
    glLinkProgram(prog);
    GLint linked = 0;
    glGetProgramiv(prog, GL_LINK_STATUS, &linked);
    if (!linked) { fprintf(stderr, "link failed\n"); return 1; }
    glUseProgram(prog);

    static const float quad[] = { -1,-1,  1,-1,  -1,1,  -1,1,  1,-1,  1,1 };
    GLuint vbo;
    glGenBuffers(1, &vbo);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof quad, quad, GL_STATIC_DRAW);
    GLint loc = glGetAttribLocation(prog, "a_pos");
    glEnableVertexAttribArray(loc);
    glVertexAttribPointer(loc, 2, GL_FLOAT, GL_FALSE, 0, (void *)0);
    GLint u_time = glGetUniformLocation(prog, "u_time");
    GLint u_res = glGetUniformLocation(prog, "u_res");
    glUniform2f(u_res, mode->hdisplay, mode->vdisplay);
    glViewport(0, 0, mode->hdisplay, mode->vdisplay);

    /* R36_FBO=1: render into an offscreen FBO instead of the scanout surface,
     * so the number is GPU throughput rather than display pacing. */
    if (getenv("R36_FBO")) {
        GLuint fbo = 0, rb = 0, st = 0;
        /* ES2 wants GL_RGBA as internalformat, ES3 rejects it and wants
         * GL_RGBA8 (0x8058) - try both and keep whichever is complete. */
        const GLenum fmts[2] = { 0x8058 /* GL_RGBA8 */, GL_RGBA };
        glGenFramebuffers(1, &fbo);
        glBindFramebuffer(GL_FRAMEBUFFER, fbo);
        glGenRenderbuffers(1, &rb);
        glBindRenderbuffer(GL_RENDERBUFFER, rb);
        for (int fi = 0; fi < 2; fi++) {
            glRenderbufferStorage(GL_RENDERBUFFER, fmts[fi],
                                  mode->hdisplay, mode->vdisplay);
            glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                                      GL_RENDERBUFFER, rb);
            st = glCheckFramebufferStatus(GL_FRAMEBUFFER);
            printf("\nFBO bench    : format 0x%x -> status 0x%x\n", fmts[fi], st);
            if (st == GL_FRAMEBUFFER_COMPLETE) break;
        }
        printf("FBO bench    : %dx%d  shader=%s\n", mode->hdisplay, mode->vdisplay,
               getenv("R36_HEAVY") ? "heavy" : "light");
        if (st != GL_FRAMEBUFFER_COMPLETE) return 1;
        if (getenv("R36_HEAVY")) {
            GLuint p2 = glCreateProgram();
            glAttachShader(p2, shader(GL_VERTEX_SHADER, VERT));
            glAttachShader(p2, shader(GL_FRAGMENT_SHADER, FRAG_HEAVY));
            glBindAttribLocation(p2, 0, "a_pos");
            glLinkProgram(p2);
            GLint ok2 = 0;
            glGetProgramiv(p2, GL_LINK_STATUS, &ok2);
            if (!ok2) { fprintf(stderr, "heavy shader link failed\n"); return 1; }
            glUseProgram(p2);
            prog = p2;
            u_time = glGetUniformLocation(p2, "u_time");
            u_res = glGetUniformLocation(p2, "u_res");
            glUniform2f(u_res, mode->hdisplay, mode->vdisplay);
            loc = glGetAttribLocation(p2, "a_pos");
            glEnableVertexAttribArray(loc);
            glVertexAttribPointer(loc, 2, GL_FLOAT, GL_FALSE, 0, (void *)0);
        }
        double b0 = now_s(), rep = b0;
        unsigned long bf = 0;
        while (now_s() - b0 < seconds) {
            glUniform1f(u_time, (float)(now_s() - b0));
            glClear(GL_COLOR_BUFFER_BIT);
            glDrawArrays(GL_TRIANGLES, 0, 6);
            glFinish();
            bf++;
            if (now_s() - rep >= 1.0) {
                FILE *f = fopen("/sys/class/devfreq/ff400000.gpu/cur_freq", "r");
                long hz = 0;
                if (f) { if (fscanf(f, "%ld", &hz) != 1) hz = 0; fclose(f); }
                printf("  %.1fs: %lu frames (%.1f fps, %.1f Mpix/s), gpu=%ld Hz\n",
                       now_s() - b0, bf, bf / (now_s() - b0),
                       bf * (mode->hdisplay * mode->vdisplay / 1e6) / (now_s() - b0), hz);
                fflush(stdout);
                rep = now_s();
            }
        }
        double bdt = now_s() - b0;
        printf("FBO RESULT   : %lu frames in %.2fs = %.1f fps, %.1f Mpix/s at %dx%d\n",
               bf, bdt, bf / bdt,
               bf * (mode->hdisplay * mode->vdisplay / 1e6) / bdt,
               mode->hdisplay, mode->vdisplay);
        printf("gl error     : 0x%x\n", glGetError());
        return 0;
    }

    struct gbm_bo *prev = NULL;
    uint32_t prev_fb = 0;
    double t0 = now_s(), report = t0;
    unsigned long frames = 0;
    while (now_s() - t0 < seconds) {
        float t = (float)(now_s() - t0);
        glUniform1f(u_time, t);
        glClear(GL_COLOR_BUFFER_BIT);
        glDrawArrays(GL_TRIANGLES, 0, 6);
        if (!eglSwapBuffers(dpy, egl_surf)) { printf("swap failed 0x%x\n", eglGetError()); break; }
        frames++;
        if (offscreen) {
            /* nothing to scan out; still throttle a little */
            usleep(2000);
        } else {
        struct gbm_bo *bo = gbm_surface_lock_front_buffer(surf);
        uint32_t handle = gbm_bo_get_handle(bo).u32;
        uint32_t stride = gbm_bo_get_stride(bo);
        uint32_t fb = 0;
        if (drmModeAddFB(fd, mode->hdisplay, mode->vdisplay, 24, 32, stride, handle, &fb) == 0) {
            drmModeSetCrtc(fd, crtc_id, fb, 0, 0, &conn->connector_id, 1, mode);
            if (prev) {
                drmModeRmFB(fd, prev_fb);
                gbm_surface_release_buffer(surf, prev);
            }
            prev = bo;
            prev_fb = fb;
        } else {
            gbm_surface_release_buffer(surf, bo);
        }
        }
        if (now_s() - report >= 1.0) {
            FILE *f = fopen("/sys/class/devfreq/ff400000.gpu/cur_freq", "r");
            long freq = 0;
            if (f) { if (fscanf(f, "%ld", &freq) != 1) freq = 0; fclose(f); }
            printf("  %.1fs: %lu frames (%.1f fps), gpu=%ld Hz\n",
                   now_s() - t0, frames, frames / (now_s() - t0), freq);
            fflush(stdout);
            report = now_s();
        }
    }
    double dt = now_s() - t0;
    printf("RESULT       : %lu frames in %.2fs = %.1f fps at %dx%d\n",
           frames, dt, frames / dt, mode->hdisplay, mode->vdisplay);
    printf("gl error     : 0x%x\n", glGetError());

    /* read the shader output back through the GPU so "it rendered" is provable
     * numerically, not just visible on the panel */
    {
        int w = 8, h = 8;
        unsigned char px[8 * 8 * 4];
        glFinish();
        glReadPixels(mode->hdisplay / 2 - 16, mode->vdisplay / 2 - 16, w, h,
                     GL_RGBA, GL_UNSIGNED_BYTE, px);
        printf("readback     : centre %dx%d sample (R,G,B) of 4 pixels\n", w, h);
        for (int i = 0; i < 4; i++) {
            int o = (i * (w * h / 4)) * 4;
            printf("               px[%2d] = %3d %3d %3d\n", i,
                   px[o], px[o + 1], px[o + 2]);
        }
        FILE *f = fopen("/tmp/gl-frame.ppm", "wb");
        if (f) {
            int W = 256, H = 192;
            unsigned char *big = malloc((size_t)W * H * 4);
            if (big) {
                glReadPixels((mode->hdisplay - W) / 2, (mode->vdisplay - H) / 2,
                             W, H, GL_RGBA, GL_UNSIGNED_BYTE, big);
                unsigned char *row = malloc((size_t)W * 3);
                if (row) {
                    fprintf(f, "P6\n%d %d\n255\n", W, H);
                    /* glReadPixels returns origin-bottom RGBA; P6 wants
                     * top-down RGB, three bytes per pixel. */
                    for (int y = 0; y < H; y++) {
                        const unsigned char *src =
                            big + (size_t)(H - 1 - y) * W * 4;
                        for (int x = 0; x < W; x++)
                            memcpy(row + x * 3, src + x * 4, 3);
                        fwrite(row, 3, W, f);
                    }
                    free(row);
                }
                free(big);
            }
            fclose(f);
            printf("readback     : /tmp/gl-frame.ppm written\n");
        }
    }

    /* leave the last frame visible for a moment so it can be screenshotted */
    if (getenv("R36_HOLD")) {
        printf("holding the last frame for %s s\n", getenv("R36_HOLD"));
        sleep(atof(getenv("R36_HOLD")));
    }
    /* hand the panel back to the Linux console before tearing anything down */
    if (orig_fb) {
        if (drmModeSetCrtc(fd, crtc_id, orig_fb, orig_x, orig_y,
                           &conn->connector_id, 1, mode) == 0) {
            if (prev) {
                drmModeRmFB(fd, prev_fb);
                gbm_surface_release_buffer(surf, prev);
                prev = NULL;
            }
            printf("restore      : console fb %u back on crtc %u\n", orig_fb, crtc_id);
        } else {
            printf("restore      : FAILED to put fb %u back on crtc %u\n",
                   orig_fb, crtc_id);
        }
    }
    eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroySurface(dpy, egl_surf);
    eglDestroyContext(dpy, ctx);
    eglTerminate(dpy);
    if (prev) gbm_surface_release_buffer(surf, prev);
    gbm_surface_destroy(surf);
    gbm_device_destroy(gbm);
    drmModeFreeConnector(conn);
    drmModeFreeResources(res);
    close(fd);
    return 0;
}
