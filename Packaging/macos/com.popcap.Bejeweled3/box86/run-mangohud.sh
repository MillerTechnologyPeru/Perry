#!/bin/sh
# run.sh with the MangoHud overlay; see PERRY_MANGOHUD there.
PERRY_MANGOHUD=1 exec "$(dirname "$(readlink -f "$0")")/run.sh" "$@"
