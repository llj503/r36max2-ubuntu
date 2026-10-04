# make && sudo cp ./r36-gles2-demo ./egl-probe /usr/local/bin/
# (device-side rebuild recipe shipped with the sources; the build system
# overrides CC/CFLAGS/LDFLAGS for the cross build)
CC ?= gcc
CFLAGS ?= -O2 -Wall
LIBS   = $(shell pkg-config --cflags --libs gbm egl glesv2 libdrm) -ldrm
all: r36-gles2-demo egl-probe
r36-gles2-demo: r36-gles2-demo.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $< $(LIBS)
egl-probe: egl-probe.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $< $(LIBS)
clean:
	rm -f r36-gles2-demo egl-probe
