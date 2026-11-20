#!/bin/bash
# Bejeweled 3's Mac build through i386 Perry under box86, full screen on
# ROCKNIX's sway (in Xwayland). Run by "Bejeweled 3.sh"; also works over ssh.
#   PERRY_ROOT  the runtime folder from Packaging/shared/box86/install-runtime.sh
#               (default: /storage/perry-i386)
#   GAME        the app (default: Bejeweled 3.app beside this script)
#   PERRY_MANGOHUD=1  the MangoHud overlay: Debian's armhf MangoHud, unpacked by
#               Packaging/shared/mangohud/fetch.sh armhf $PERRY_ROOT/mangohud
here=$(cd "$(dirname "$0")" && pwd)
: "${PERRY_ROOT:=/storage/perry-i386}"
: "${GAME:=$here/Bejeweled 3.app}"
# ROCKNIX's own box86 (0.3.9) crashes as Perry starts; see the runtime's README.
BOX86=${BOX86:-$PERRY_ROOT/box86}
lib=$PERRY_ROOT/sysroot/usr/lib

# PortMaster puts 64-bit libraries and a MangoHud preload first; box86, an
# armhf process, needs the armhf ones.
unset LD_PRELOAD
export LD_LIBRARY_PATH=/usr/lib32
if [ -n "$PERRY_MANGOHUD" ]; then
    # Preloaded into box86 itself, which draws with the native GL.
    mangohud=${MANGOHUD_ROOT:-$PERRY_ROOT/mangohud}/usr/lib/arm-linux-gnueabihf
    export LD_LIBRARY_PATH=$mangohud:$LD_LIBRARY_PATH
    export LD_PRELOAD=$mangohud/mangohud/libMangoHud_shim.so MANGOHUD=1
fi

export BOX86_LD_LIBRARY_PATH=$lib/swift/linux:$lib/i386-linux-gnu:$lib/i386-linux-gnu/pulseaudio
export BOX86_LD_PRELOAD=$PERRY_ROOT/libperrybox.so:$PERRY_ROOT/libc23box.so
# The i386 GLib and GStreamer, for sound: box86's wrapper for the native GLib
# lacks g_weak_ref_clear, which GStreamer needs.
glib=libglib-2.0.so.0:libgobject-2.0.so.0:libgmodule-2.0.so.0:libgio-2.0.so.0
gst=libgstreamer-1.0.so.0:libgstbase-1.0.so.0:libgstapp-1.0.so.0:libgstaudio-1.0.so.0:libgsttag-1.0.so.0:libgstpbutils-1.0.so.0:libgstvideo-1.0.so.0
export BOX86_EMULATED_LIBS=libwayland-client.so.0:libdrm.so.2:libpulse.so.0:libpulse-simple.so.0:$glib:$gst

export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/var/run/0-runtime-dir} DISPLAY=${DISPLAY:-:0} SDL_VIDEODRIVER=x11
export SDL_VIDEO_X11_XINPUT2=0
export GST_PLUGIN_SYSTEM_PATH_1_0=$PERRY_ROOT/gst-plugins GST_PLUGIN_SYSTEM_PATH=$PERRY_ROOT/gst-plugins GST_PLUGIN_PATH_1_0=
export GST_REGISTRY=$PERRY_ROOT/gst-registry.i686.bin GST_REGISTRY_FORK=no

export PERRY_UNIMPLEMENTED=continue PERRY_OBJC_UNRECOGNIZED=continue
export SDL_APP_ID=com.popcap.Bejeweled3
exec "$BOX86" "$PERRY_ROOT/bin/perry32" "$GAME" "$@"
