#!/bin/bash
# Automated Tibia 7.7 Server Setup Script
# For Debian 13 on VPS with IP set to $IP
# User: $USER (with sudo rights)
# Game tarball: /home/$USER/downloads/tibia-game.tarball.tar.xz

IP=168.119.123.103

set -e  # Exit on error

echo "=== Starting Tibia 7.7 Server Setup ==="

# Step 1: Update system and install dependencies
echo "=== Installing system dependencies ==="
sudo apt update
sudo apt install -y build-essential g++ gcc make git libssl-dev sqlite3 wget

# Install Go 1.25.2 (required for web server)
echo "=== Installing Go 1.25.2 ==="
wget -q https://go.dev/dl/go1.25.2.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.25.2.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
rm go1.25.2.linux-amd64.tar.gz

# Step 2: Create service user
echo "=== Creating tibia service user ==="
sudo useradd -r -m -s /bin/bash tibia || true  # Ignore if already exists
sudo mkdir -p /opt/tibia/{game,login,querymanager,web}
sudo chown -R tibia:tibia /opt/tibia

# Step 3: Clone and build all services
echo "=== Cloning repositories ==="
cd /home/$USER
mkdir -p tibia-build
cd tibia-build

# Clone all repos
git clone https://github.com/fusion32/tibia-querymanager.git
git clone https://github.com/fusion32/tibia-game.git
git clone https://github.com/fusion32/tibia-login.git
git clone https://github.com/fusion32/tibia-web.git

# Build Query Manager
echo "=== Building Query Manager ==="
cd tibia-querymanager
make clean && make
cd ..

# Build Game Server
echo "=== Building Game Server ==="
cd tibia-game
make clean && make
cd ..

# Build Login Server
echo "=== Building Login Server ==="
cd tibia-login
make clean && make
cd ..

# Build Web Server
echo "=== Building Web Server ==="
cd tibia-web
/usr/local/go/bin/go build -o build/tibia-web
cd ..

# Step 4: Prepare game files
echo "=== Preparing game files ==="
cd /tmp
tar -xf /home/$USER/downloads/tibia-game.tarball.tar.xz

# Copy compiled binary and RSA key
cp /home/$USER/tibia-build/tibia-game/build/game /tmp/tibia-game.tarball/bin/game
cp /home/$USER/tibia-build/tibia-game/tibia.pem /tmp/tibia-game.tarball/

# Step 5: Setup Query Manager
echo "=== Setting up Query Manager ==="
sudo cp -r /home/$USER/tibia-build/tibia-querymanager/* /opt/tibia/querymanager/
# Make sure the binary is in the right place
sudo cp /home/$USER/tibia-build/tibia-querymanager/build/querymanager /opt/tibia/querymanager/querymanager
cd /opt/tibia/querymanager
sudo -u tibia sqlite3 tibia.db < sql/schema.sql
sudo -u tibia sqlite3 tibia.db < sql/init.sql
sudo chmod 600 /opt/tibia/querymanager/tibia.db

# Step 6: Setup Game Server
echo "=== Setting up Game Server ==="
sudo cp -r /tmp/tibia-game.tarball/* /opt/tibia/game/
sudo chown -R tibia:tibia /opt/tibia/game
sudo chmod 600 /opt/tibia/game/tibia.pem
sudo chmod -R 755 /opt/tibia/game/usr

# Update .tibia config with correct format
echo "=== Updating game server config ==="

# Encode the query manager password
# Password "a6glaf0c" with key "Pm-,o%yD" becomes "nXE?/>j`"
# Using the formula: encoded[i] = (key[i] - password[i] + 0x5E) % 0x5E + 0x21
ENCODED_PW='nXE?/>j`'

sudo tee /opt/tibia/game/.tibia > /dev/null << EOF
# Tibia - Graphical Multi-User-Dungeon
# .tibia: Konfigurationsdatei (Game-Server)

# Verzeichnisse
BINPATH     = "/opt/tibia/game/bin"
MAPPATH     = "/opt/tibia/game/map"
ORIGMAPPATH = "/opt/tibia/game/origmap"
DATAPATH    = "/opt/tibia/game/dat"
USERPATH    = "/opt/tibia/game/usr"
LOGPATH     = "/opt/tibia/game/log"
SAVEPATH    = "/opt/tibia/game/save"
MONSTERPATH = "/opt/tibia/game/mon"
NPCPATH     = "/opt/tibia/game/npc"

# SharedMemories
SHM = 10011

# DebugLevel
DebugLevel = 2

# Server-Takt
Beat = 50

# QueryManager
QueryManager = {("127.0.0.1",7173,"${ENCODED_PW}"),("127.0.0.1",7173,"${ENCODED_PW}"),("127.0.0.1",7173,"${ENCODED_PW}"),("127.0.0.1",7173,"${ENCODED_PW}")}

# Weltstatus
World = "Zanera"
State = public
EOF
sudo chown tibia:tibia /opt/tibia/game/.tibia

# Step 7: Setup Login Server
echo "=== Setting up Login Server ==="
sudo cp -r /home/$USER/tibia-build/tibia-login/* /opt/tibia/login/
# Make sure the binary is in the right place
sudo cp /home/$USER/tibia-build/tibia-login/build/login /opt/tibia/login/login
sudo cp /opt/tibia/game/tibia.pem /opt/tibia/login/
sudo chown -R tibia:tibia /opt/tibia/login
sudo chmod 600 /opt/tibia/login/tibia.pem

# Step 8: Setup Web Server
echo "=== Setting up Web Server ==="
sudo cp -r /home/$USER/tibia-build/tibia-web/* /opt/tibia/web/
# Make sure the binary is in the right place
sudo cp /home/$USER/tibia-build/tibia-web/build/tibia-web /opt/tibia/web/tibia-web
sudo chown -R tibia:tibia /opt/tibia/web

# Update web server config to use port 8080 (avoid root requirement)
sudo tee /opt/tibia/web/config.cfg > /dev/null << 'EOF'
HttpPort = 8080
QueryManagerHost = "localhost"
QueryManagerPort = 7173
QueryManagerPassword = "a6glaf0c"
EOF
sudo chown tibia:tibia /opt/tibia/web/config.cfg

# Step 9: Install systemd services
echo "=== Installing systemd services ==="

# Copy service files
sudo cp /home/$USER/tibia-build/tibia-querymanager/tibia-querymanager.service /etc/systemd/system/
sudo cp /home/$USER/tibia-build/tibia-game/tibia-game.service /etc/systemd/system/
sudo cp /home/$USER/tibia-build/tibia-login/tibia-login.service /etc/systemd/system/
sudo cp /home/$USER/tibia-build/tibia-web/tibia-web.service /etc/systemd/system/

# Update service paths
sudo sed -i 's|WorkingDirectory=.*|WorkingDirectory=/opt/tibia/querymanager|' /etc/systemd/system/tibia-querymanager.service
sudo sed -i 's|ExecStart=.*|ExecStart=/opt/tibia/querymanager/querymanager|' /etc/systemd/system/tibia-querymanager.service

sudo sed -i 's|WorkingDirectory=.*|WorkingDirectory=/opt/tibia/game|' /etc/systemd/system/tibia-game.service
sudo sed -i 's|ExecStart=.*|ExecStart=/opt/tibia/game/bin/game|' /etc/systemd/system/tibia-game.service

sudo sed -i 's|WorkingDirectory=.*|WorkingDirectory=/opt/tibia/login|' /etc/systemd/system/tibia-login.service
sudo sed -i 's|ExecStart=.*|ExecStart=/opt/tibia/login/login|' /etc/systemd/system/tibia-login.service

sudo sed -i 's|WorkingDirectory=.*|WorkingDirectory=/opt/tibia/web|' /etc/systemd/system/tibia-web.service
sudo sed -i 's|ExecStart=.*|ExecStart=/opt/tibia/web/tibia-web|' /etc/systemd/system/tibia-web.service

# Fix user in all service files (they use different user names by default)
echo "=== Fixing service users ==="
sudo sed -i 's|User=.*|User=tibia|' /etc/systemd/system/tibia-*.service
sudo sed -i 's|Group=.*|Group=tibia|' /etc/systemd/system/tibia-*.service

# Reload systemd
sudo systemctl daemon-reload

# Step 10: Configure firewall
echo "=== Configuring firewall ==="
sudo apt install -y ufw
sudo ufw allow 7171/tcp  # Login server
sudo ufw allow 7172/tcp  # Game server
sudo ufw allow 8080/tcp  # Web server
sudo ufw allow 22/tcp    # SSH (don't lock yourself out!)
sudo ufw --force enable

# Step 11: Start all services
echo "=== Starting services ==="

# Start in correct order
sudo systemctl enable tibia-querymanager
sudo systemctl start tibia-querymanager
sleep 5  # Give query manager time to start

sudo systemctl enable tibia-game
sudo systemctl start tibia-game

sudo systemctl enable tibia-login
sudo systemctl start tibia-login

sudo systemctl enable tibia-web
sudo systemctl start tibia-web

# Step 12: Verify services
echo "=== Verifying services ==="
sudo systemctl status tibia-querymanager --no-pager
sudo systemctl status tibia-game --no-pager
sudo systemctl status tibia-login --no-pager
sudo systemctl status tibia-web --no-pager

# Clean up
echo "=== Cleaning up ==="
rm -rf /tmp/tibia-game.tarball

echo "=== Setup Complete! ==="
echo "Server IP: 168.119.123.103"
echo "Game Port: 7172"
echo "Login Port: 7171"
echo "Web Interface: http://168.119.123.103:8080"
echo ""
echo "Default test account: 111111/tibia"
echo "Default characters: Gamemaster (GM), Player"
echo ""
echo "To check logs:"
echo "  sudo journalctl -u tibia-querymanager -f"
echo "  sudo journalctl -u tibia-game -f"
echo "  sudo journalctl -u tibia-login -f"
echo "  sudo journalctl -u tibia-web -f"