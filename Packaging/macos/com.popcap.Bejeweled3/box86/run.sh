#!/bin/bash
# Bejeweled 3's Mac build on desktop ARM Linux, through i386 Perry under box86,
# in an X11 window (Xwayland on a Wayland desktop). Arguments go to the game.
#   PERRY_ROOT  the runtime folder from Packaging/shared/box86/install-runtime.sh
#               (default: ~/Perry-i386)
#   GAME        the app (default: ~/Games/Bejeweled 3.app)
#   BOX86       box86 to run (default: $PERRY_ROOT/box86 if there, else box86)
#   PERRY_MANGOHUD=1  the MangoHud overlay: Debian's armhf MangoHud, unpacked by
#               Packaging/shared/mangohud/fetch.sh armhf $PERRY_ROOT/mangohud
: "${PERRY_ROOT:=$HOME/Perry-i386}"
: "${GAME:=$HOME/Games/Bejeweled 3.app}"
[ -z "$BOX86" ] && { [ -x "$PERRY_ROOT/box86" ] && BOX86=$PERRY_ROOT/box86 || BOX86=box86; }
lib=$PERRY_ROOT/sysroot/usr/lib

export BOX86_LD_LIBRARY_PATH=$lib/swift/linux:$lib/i386-linux-gnu:$lib/i386-linux-gnu/pulseaudio
export BOX86_LD_PRELOAD=$PERRY_ROOT/libperrybox.so:$PERRY_ROOT/libc23box.so
export BOX86_EMULATED_LIBS=libwayland-client.so.0:libdrm.so.2:libpulse.so.0:libpulse-simple.so.0

# The desktop's Xwayland, also from a terminal that isn't in the session.
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export DISPLAY=${DISPLAY:-:0} SDL_VIDEODRIVER=x11
[ -z "$XAUTHORITY" ] && export XAUTHORITY=$(ls -t "$XDG_RUNTIME_DIR"/.mutter-Xwaylandauth.* 2>/dev/null | head -n 1)
# XInput2 events hold doubles, which i386 and ARM lay out differently;
# without it, touches arrive as clicks.
export SDL_VIDEO_X11_XINPUT2=0

export GST_PLUGIN_SYSTEM_PATH_1_0=$PERRY_ROOT/gst-plugins GST_PLUGIN_SYSTEM_PATH=$PERRY_ROOT/gst-plugins GST_PLUGIN_PATH_1_0=
export GST_REGISTRY=$PERRY_ROOT/gst-registry.i686.bin GST_REGISTRY_FORK=no

if [ -n "$PERRY_MANGOHUD" ]; then
    # Preloaded into box86 itself, an armhf process drawing with the native GL.
    mangohud=${MANGOHUD_ROOT:-$PERRY_ROOT/mangohud}/usr/lib/arm-linux-gnueabihf
    export LD_LIBRARY_PATH=$mangohud${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    export LD_PRELOAD=$mangohud/mangohud/libMangoHud_shim.so MANGOHUD=1
fi

export PERRY_UNIMPLEMENTED=continue PERRY_OBJC_UNRECOGNIZED=continue
# The desktop entry's StartupWMClass.
export SDL_APP_ID=com.popcap.Bejeweled3
exec "$BOX86" "$PERRY_ROOT/bin/perry32" "$GAME" "$@"
