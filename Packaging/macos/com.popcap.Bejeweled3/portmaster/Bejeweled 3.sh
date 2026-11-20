#!/bin/bash
# Bejeweled 3, the Mac build, run by Perry's i386 loader under box86.

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source $controlfolder/control.txt
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls

GAMEDIR="/$directory/ports/bejeweled3"
cd "$GAMEDIR"

> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

if [ ! -d "$GAMEDIR/Bejeweled 3.app" ]; then
  pm_message "Copy Bejeweled 3.app, from Steam's Mac version, into ports/bejeweled3."
  sleep 10
  exit 1
fi

# The left stick moves the mouse pointer; A or R1 clicks, L1 right-clicks,
# B or Start is Escape. Select + Start quits the game.
$GPTOKEYB "perry32" -c "$GAMEDIR/bejeweled3.gptk" &

./run.sh

pm_finish
