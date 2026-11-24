#!/bin/bash
# Halo's Mac build through i386 Perry under box86, full screen on ROCKNIX's
# sway (in Xwayland). Run by "Halo.sh"; also works over ssh.
#   PERRY_ROOT  the runtime folder from Packaging/shared/box86/install-runtime.sh
#               (default: /storage/perry-i386)
#   GAME        the app (default: Halo.app beside this script)
#   DISC        the Halo disc's contents (default: disc beside this script),
#               which the game finds as a mounted disc named "Halo Universal"
#   PERRY_MANGOHUD=1  the MangoHud overlay: Debian's armhf MangoHud, unpacked by
#               Packaging/shared/mangohud/fetch.sh armhf $PERRY_ROOT/mangohud
here=$(cd "$(dirname "$0")" && pwd)
: "${PERRY_ROOT:=/storage/perry-i386}"
: "${GAME:=$here/Halo.app}"
: "${DISC:=$here/disc}"
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
# Halo maps its game state at 0x40000000, where its saved data points into,
# and box86 puts its own pages from that address up unless told otherwise
# (BOX86_MMAP_BASE, from Packaging/shared/box86/box86-mmap-base.patch).
export BOX86_MMAP_BASE=0x48000000
# The i386 GLib and GStreamer, for sound: box86's wrapper for the native GLib
# lacks g_weak_ref_clear, which GStreamer needs.
glib=libglib-2.0.so.0:libgobject-2.0.so.0:libgmodule-2.0.so.0:libgio-2.0.so.0
gst=libgstreamer-1.0.so.0:libgstbase-1.0.so.0:libgstapp-1.0.so.0:libgstaudio-1.0.so.0:libgsttag-1.0.so.0:libgstpbutils-1.0.so.0:libgstvideo-1.0.so.0
# The i386 fontconfig and FreeType too: box86's wrapper for the native one lacks
# FcConfigAppFontAddDir, which Core Graphics needs for an app's own fonts. And
# cairo with them, with what it draws through: the machine's cairo would be
# handed the i386 fontconfig's patterns and FreeType's faces, which aren't its
# own libraries', and no text is drawn.
export BOX86_EMULATED_LIBS=libwayland-client.so.0:libdrm.so.2:libpulse.so.0:libpulse-simple.so.0:libfontconfig.so.1:libfreetype.so.6:libcairo.so.2:libpixman-1.so.0:libpng16.so.16:libexpat.so.1:$glib:$gst

export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/var/run/0-runtime-dir} DISPLAY=${DISPLAY:-:0} SDL_VIDEODRIVER=x11
export SDL_VIDEO_X11_XINPUT2=0
export GST_PLUGIN_SYSTEM_PATH_1_0=$PERRY_ROOT/gst-plugins GST_PLUGIN_SYSTEM_PATH=$PERRY_ROOT/gst-plugins GST_PLUGIN_PATH_1_0=
export GST_REGISTRY=$PERRY_ROOT/gst-registry.i686.bin GST_REGISTRY_FORK=no

# Halo's preferences, profiles and saved games. It refuses a Documents folder
# whose path has a period in it, so the container's has none.
mkdir -p "$here/conf"
export PERRY_CONTAINER=$here/conf
export PERRY_DISCS="Halo Universal=$DISC"
export PERRY_UNIMPLEMENTED=continue PERRY_OBJC_UNRECOGNIZED=continue
export SDL_APP_ID=com.macsoft.halo
exec "$BOX86" "$PERRY_ROOT/bin/perry32" "$GAME" "$@"
