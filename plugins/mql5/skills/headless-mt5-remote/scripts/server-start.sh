#!/bin/bash
# Start the complete headless MT5 stack on gpu-host
# Usage: ssh gpu-host 'bash -s' < scripts/server-start.sh

export WINEPREFIX=~/.mt5
export DISPLAY=:99
export WINEDEBUG=-all

# Kill existing processes
wineserver -k 2>/dev/null
pkill -f "Xvfb :99" 2>/dev/null
pkill x11vnc 2>/dev/null
pkill autocutsel 2>/dev/null
pkill -f xfce 2>/dev/null
sleep 3

# 1. Virtual display
Xvfb :99 -ac -screen 0 1680x1050x24 &
sleep 1

# 2. Key repeat (Xvfb default has no repeat)
xset r rate 200 30

# 3. XFCE desktop
dbus-launch --exit-with-session startxfce4 &
sleep 5

# 4. Clipboard bridge (X11 CLIPBOARD + PRIMARY)
autocutsel -s CLIPBOARD -fork
autocutsel -s PRIMARY -fork

# 5. VNC server
x11vnc -display :99 -rfbport 5900 -forever -localhost -noncache -nopw -repeat -xkb &
sleep 1

# 6. MetaTrader 5
wine "$HOME/.mt5/drive_c/Program Files/MetaTrader 5/terminal64.exe" /portable &
sleep 3

echo "=== Stack running ==="
ps aux | grep -E "Xvfb|xfce4-session|x11vnc|terminal64" | grep -v grep
