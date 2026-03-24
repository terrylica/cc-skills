# Server Setup — Headless MT5 on Ubuntu 24.04

## Prerequisites

- Ubuntu 24.04 LTS (x86_64)
- SSH access
- No physical monitor required

## Step 1: Install Wine 10.0 Stable

```bash
sudo dpkg --add-architecture i386
sudo mkdir -pm755 /etc/apt/keyrings
sudo wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key
sudo wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/noble/winehq-noble.sources
sudo apt update
sudo apt install --install-recommends winehq-stable
```

### Pin Wine version (prevent auto-upgrade to broken 11.x)

```bash
sudo apt-mark hold winehq-stable wine-stable wine-stable-amd64 wine-stable-i386
```

### Verify

```bash
wine --version  # Should show wine-10.0
```

## Step 2: Install Display + Desktop + VNC

```bash
sudo apt install -y xvfb x11vnc xfce4 xfce4-terminal dbus-x11 xclip xsel autocutsel
```

### Remove lock screen (prevents password prompts)

```bash
sudo apt remove -y light-locker xfce4-screensaver
```

### Disable PolicyKit Wi-Fi prompts

```bash
sudo tee /etc/polkit-1/localauthority/50-local.d/allow-network.pkla << EOF
[Allow Network Management]
Identity=unix-user:*
Action=org.freedesktop.NetworkManager.*
ResultAny=yes
ResultInactive=yes
ResultActive=yes
EOF
```

## Step 3: Create Wine Prefix + Install MT5

```bash
export WINEPREFIX=~/.mt5 WINEARCH=win64 WINEDEBUG=-all
wineboot --init

# Download MT5
wget -O /tmp/mt5setup.exe https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe

# Start display and install
Xvfb :99 -ac -screen 0 1680x1050x24 &
DISPLAY=:99 wine /tmp/mt5setup.exe /auto
```

## Step 4: Deploy Custom DLL + EA

```bash
# From macOS:
scp tick_writer.dll gpu-host:~/.mt5/drive_c/Program\ Files/MetaTrader\ 5/MQL5/Libraries/
scp TickCollector.mq5 gpu-host:~/.mt5/drive_c/Program\ Files/MetaTrader\ 5/MQL5/Experts/
```

## Step 5: Enable systemd Linger

```bash
loginctl enable-linger $USER  # Services survive logout
```

## Step 6: First-Time FXView Login

Requires VNC access for GUI interaction:

```bash
# On server:
x11vnc -display :99 -rfbport 5900 -forever -localhost -noncache -nopw -repeat -xkb &

# On macOS:
ssh -L 5900:localhost:5900 tca@gpu-host
# Then connect TigerVNC to localhost:5900
```

Log into FXView, check "Save password", close the dialog.

## Step 7: Start the Full Stack

```bash
./scripts/server-start.sh
```
