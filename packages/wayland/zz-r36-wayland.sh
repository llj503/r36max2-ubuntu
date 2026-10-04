# /etc/profile.d/zz-r36-wayland.sh
# When the Weston session is up, an SSH shell should be able to start a Wayland
# client without remembering the socket name.  Only set it while the socket
# actually exists, otherwise a client would fail with a confusing "error
# connecting to display".
if [ -S /run/wayland/wayland-0 ]; then
    export XDG_RUNTIME_DIR=/run/wayland
    export WAYLAND_DISPLAY=wayland-0
fi
