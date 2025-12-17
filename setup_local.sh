#!/bin/bash
# Tibia 7.7 Local Development Setup Script
# Copies everything to ~/tibia_local and runs from there

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_DIR="$HOME/tibia_local"

echo "=== Tibia 7.7 Local Development Setup ==="
echo "Local directory: $LOCAL_DIR"

# Step 1: Check dependencies
echo "=== Checking dependencies ==="

if ! command -v g++ &> /dev/null; then
    echo "Error: g++ not found. Please install build-essential package."
    echo "  sudo apt install build-essential"
    exit 1
fi

if ! command -v make &> /dev/null; then
    echo "Error: make not found. Please install make package."
    echo "  sudo apt install make"
    exit 1
fi

if ! pkg-config --exists libcrypto; then
    echo "Error: libcrypto not found. Please install libssl-dev package."
    echo "  sudo apt install libssl-dev"
    exit 1
fi

if ! command -v sqlite3 &> /dev/null; then
    echo "Error: sqlite3 not found. Please install sqlite3 package."
    echo "  sudo apt install sqlite3"
    exit 1
fi

echo "✓ All dependencies found"

# Step 2: Create local directory and copy everything
echo "=== Creating local directory and copying files ==="
rm -rf "$LOCAL_DIR"
mkdir -p "$LOCAL_DIR"

# Copy all service directories
cp -r "$SCRIPT_DIR/../game" "$LOCAL_DIR/"
cp -r "$SCRIPT_DIR/../tibia-login" "$LOCAL_DIR/login"
cp -r "$SCRIPT_DIR/../tibia-querymanager" "$LOCAL_DIR/querymanager"

# Step 3: Check for existing binaries and optionally recompile
echo "=== Checking for existing binaries ==="

# Check if binaries exist in original directories
BINARIES_EXIST=true
if [ ! -f "$SCRIPT_DIR/../tibia-game/build/game" ]; then
    echo "⚠ Game server binary not found in tibia-game/build/"
    BINARIES_EXIST=false
fi
if [ ! -f "$SCRIPT_DIR/../tibia-login/build/login" ]; then
    echo "⚠ Login server binary not found in tibia-login/build/"
    BINARIES_EXIST=false
fi
if [ ! -f "$SCRIPT_DIR/../tibia-querymanager/build/querymanager" ]; then
    echo "⚠ Query manager binary not found in tibia-querymanager/build/"
    BINARIES_EXIST=false
fi

if $BINARIES_EXIST; then
    echo "✓ Found existing compiled binaries"
    echo ""
    read -p "Do you want to recompile all services? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        RECOMPILE=true
        echo "Will recompile all services..."
    else
        RECOMPILE=false
        echo "Using existing binaries..."
    fi
else
    echo "Some binaries are missing, will compile all services..."
    RECOMPILE=true
fi

if $RECOMPILE; then
    echo "=== Building services ==="

    # Calculate number of cores to use (half of available cores)
    AVAILABLE_CORES=$(nproc)
    CORES_TO_USE=$((AVAILABLE_CORES / 2))
    # Ensure at least 1 core is used
    if [ $CORES_TO_USE -lt 1 ]; then
        CORES_TO_USE=1
    fi
    echo "Using $CORES_TO_USE cores for compilation (half of $AVAILABLE_CORES available cores)"

    # Build Query Manager
    echo "Building Query Manager..."
    cd "$SCRIPT_DIR/../tibia-querymanager"
    make clean && make -j$CORES_TO_USE

    # Build Game Server
    echo "Building Game Server..."
    cd "$SCRIPT_DIR/../tibia-game"
    make clean && make -j$CORES_TO_USE

    # Build Login Server
    echo "Building Login Server..."
    cd "$SCRIPT_DIR/../tibia-login"
    make clean && make -j$CORES_TO_USE

    echo "✓ All services compiled successfully"
fi

# Copy binaries to LOCAL_DIR
echo "=== Copying binaries to local directory ==="
cp "$SCRIPT_DIR/../tibia-game/build/game" "$LOCAL_DIR/game/bin/game"
cp "$SCRIPT_DIR/../tibia-game/tibia.pem" "$LOCAL_DIR/game/tibia.pem"
cp "$SCRIPT_DIR/../tibia-game/tibia.pem" "$LOCAL_DIR/login/tibia.pem"
cp "$SCRIPT_DIR/../tibia-login/build/login" "$LOCAL_DIR/login/build/login"
cp "$SCRIPT_DIR/../tibia-querymanager/build/querymanager" "$LOCAL_DIR/querymanager/build/querymanager"

# Step 4: Setup Query Manager database
echo "=== Setting up Query Manager database ==="
cd "$LOCAL_DIR/querymanager"

# Create database schema
sqlite3 tibia.db < sql/schema.sql

# Insert initial data if init.sql exists
if [ -f "sql/init.sql" ]; then
    sqlite3 tibia.db < sql/init.sql
    echo "✓ Initial database data inserted"
else
    echo "⚠ No init.sql found - database will be empty"
fi

# Step 5: Update configuration files
echo "=== Updating configuration files ==="
cd "$LOCAL_DIR/game"

# Store the encoded password in a variable
ENCODED_PW='nXE?/>j`'

# Update game server config (.tibia) with correct paths
cat > .tibia << EOF
# Tibia - Graphical Multi-User-Dungeon
# .tibia: Konfigurationsdatei (Game-Server)

# Verzeichnisse
BINPATH     = "$LOCAL_DIR/game/bin"
MAPPATH     = "$LOCAL_DIR/game/map"
ORIGMAPPATH = "$LOCAL_DIR/game/origmap"
DATAPATH    = "$LOCAL_DIR/game/dat"
USERPATH    = "$LOCAL_DIR/game/usr"
LOGPATH     = "$LOCAL_DIR/game/log"
SAVEPATH    = "$LOCAL_DIR/game/save"
MONSTERPATH = "$LOCAL_DIR/game/mon"
NPCPATH     = "$LOCAL_DIR/game/npc"

# SharedMemories
SHM = 10011

# DebugLevel
DebugLevel = 3

# Server-Takt
Beat = 50

# QueryManager
QueryManager = {("127.0.0.1",7173,"$ENCODED_PW"),("127.0.0.1",7173,"$ENCODED_PW"),("127.0.0.1",7173,"$ENCODED_PW"),("127.0.0.1",7173,"$ENCODED_PW")}

# Weltstatus
World = "Zanera"
State = public
EOF

# Update login server config
cat > login.cfg << 'EOF'
MOTD                  = "Welcome to Local Tibia Test Server!"
UpdateRate            = 20
LoginPort             = 7171
MaxConnections        = 10
LoginTimeout          = 10s
QueryManagerHost      = "127.0.0.1"
QueryManagerPort      = 7173
QueryManagerPassword  = "a6glaf0c"
EOF

# Update query manager config
cat > config.cfg << 'EOF'
# Database Config
DatabaseFile            = "tibia.db"
MaxCachedStatements     = 100

# HostCache Config
MaxCachedHostNames      = 100
HostNameExpireTime      = 30m

# Connection Config
UpdateRate              = 20
QueryManagerPort        = 7173
QueryManagerPassword    = "a6glaf0c"
MaxConnections          = 25
MaxConnectionIdleTime   = 5m
MaxConnectionPacketSize = 1M
EOF

# Step 6: Create startup scripts
echo "=== Creating startup scripts ==="

# Start all services script
cat > "$LOCAL_DIR/start_all.sh" << 'EOF'
#!/bin/bash
set -e

echo "Starting Tibia 7.7 Local Server..."

# Kill any existing processes
pkill -f querymanager || true
pkill -f "bin/game" || true
pkill -f login || true

sleep 2

# Start Query Manager first
echo "Starting Query Manager..."
cd querymanager
./build/querymanager &
QUERY_PID=$!
cd ..

echo "Query Manager started with PID: $QUERY_PID"
sleep 3

# Start Game Server
echo "Starting Game Server..."
cd game
./bin/game &
GAME_PID=$!
cd ..

echo "Game Server started with PID: $GAME_PID"
sleep 2

# Start Login Server
echo "Starting Login Server..."
cd login
cp config.cfg login.cfg 2>/dev/null || true
./build/login &
LOGIN_PID=$!
cd ..

echo "Login Server started with PID: $LOGIN_PID"

# Save PIDs for later
echo $QUERY_PID > .querymanager.pid
echo $GAME_PID > .game.pid
echo $LOGIN_PID > .login.pid

echo ""
echo "=== All services started! ==="
echo "Query Manager: PID $QUERY_PID (port 7173)"
echo "Game Server:   PID $GAME_PID (port 7172)"
echo "Login Server:  PID $LOGIN_PID (port 7171)"
echo ""
echo "To stop all services: ./stop_all.sh"
echo "To view logs: tail -f game/log/*.log"
EOF

# Stop all services script
cat > "$LOCAL_DIR/stop_all.sh" << 'EOF'
#!/bin/bash
echo "Stopping Tibia 7.7 Local Server..."

if [ -f .querymanager.pid ]; then
    kill $(cat .querymanager.pid) 2>/dev/null || true
    rm .querymanager.pid
fi

if [ -f .game.pid ]; then
    kill $(cat .game.pid) 2>/dev/null || true
    rm .game.pid
fi

if [ -f .login.pid ]; then
    kill $(cat .login.pid) 2>/dev/null || true
    rm .login.pid
fi

# Kill any remaining processes
pkill -f "build/querymanager" 2>/dev/null || true
pkill -f "bin/game" 2>/dev/null || true
pkill -f "build/login" 2>/dev/null || true

echo "All services stopped"
EOF

# Make scripts executable
chmod +x "$LOCAL_DIR/start_all.sh" "$LOCAL_DIR/stop_all.sh"

# Step 7: Set permissions
echo "=== Setting permissions ==="
chmod 600 "$LOCAL_DIR/game/tibia.pem" "$LOCAL_DIR/login/tibia.pem"
chmod 644 "$LOCAL_DIR/querymanager/tibia.db"

# Step 8: Create README
echo "=== Creating documentation ==="

cat > README.md << 'EOF'
# Tibia 7.7 Local Test Server

## Quick Start

1. Start all services:
   ```bash
   ./start_all.sh
   ```

2. Stop all services:
   ```bash
   ./stop_all.sh
   ```

## Server Information

- **Login Server**: localhost:7171
- **Game Server**: localhost:7172
- **Query Manager**: localhost:7173

## Client Setup

Use the IP changer tool to patch your Tibia 7.7 client:

```bash
cd tibia-ipchanger-linux
make
./ipchanger /path/to/Tibia.exe localhost
```

## Important Notes

- This setup uses the default password: `a6glaf0c`
- Game data is copied from the original game directory
- Database is empty by default - use `sql/init.sql` to add test data
- All services run in foreground for easy debugging

## Files Structure

- `bin/game` - Game server binary
- `login` - Login server binary
- `querymanager` - Query manager binary
- `tibia.db` - SQLite database
- `*.cfg` - Configuration files
- `*.pem` - RSA keys
- `map/` - World map data
- `dat/` - Game data files
- `usr/` - Character data
- `log/` - Log files
EOF

echo ""
echo "=== Local Setup Complete! ==="
echo "Local directory: $LOCAL_DIR"
echo ""
echo "Directory structure:"
echo "  $LOCAL_DIR/game/       - Game server with all game data"
echo "  $LOCAL_DIR/login/      - Login server"
echo "  $LOCAL_DIR/querymanager/ - Query manager with database"
echo ""
echo "To start all services:"
echo "  cd $LOCAL_DIR && ./start_all.sh"
echo ""
echo "To stop all services:"
echo "  cd $LOCAL_DIR && ./stop_all.sh"
echo ""
echo "See README.md for more information."
