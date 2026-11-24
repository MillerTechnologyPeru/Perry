#!/bin/bash
# Halo, MacSoft's Mac build, run by Perry's i386 loader under box86.

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

GAMEDIR="/$directory/ports/halo"
cd "$GAMEDIR"

> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

if [ ! -d "$GAMEDIR/Halo.app" ]; then
  pm_message "Copy Halo.app, installed from your Halo disc, into ports/halo."
  sleep 10
  exit 1
fi
if [ ! -d "$GAMEDIR/disc" ]; then
  pm_message "Copy your Halo disc's contents into ports/halo/disc: the game looks for its disc."
  sleep 10
  exit 1
fi

# The left stick walks, the right one looks; see halo.gptk. Select + Start
# quits the game.
$GPTOKEYB "perry32" -c "$GAMEDIR/halo.gptk" &

./run.sh

pm_finish
