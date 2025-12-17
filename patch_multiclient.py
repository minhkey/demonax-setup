#!/usr/bin/env python3
"""
Tibia 7.70 Multiclient Patcher
Patches the Tibia.exe client to allow multiple instances
The correct offset and byte to edit was found here:
https://otland.net/threads/mc-multiclient-hex-7-4-at-10-x.130933/
"""

import sys
import os
import shutil

def patch_client(client_path):
    """Patch Tibia 7.70 client for multiclient support"""

    # Tibia 7.70 multiclient patch offset
    PATCH_OFFSET = 0xA9D5C
    ORIGINAL_BYTE = 0x7E
    PATCHED_BYTE = 0xEB

    # Create backup
    backup_path = client_path + '.backup'
    if not os.path.exists(backup_path):
        print(f"Creating backup: {backup_path}")
        shutil.copy2(client_path, backup_path)
    else:
        print(f"Backup already exists: {backup_path}")

    # Read the file
    with open(client_path, 'rb') as f:
        data = bytearray(f.read())

    # Check if already patched
    if data[PATCH_OFFSET] == PATCHED_BYTE:
        print("Client is already patched for multiclient!")
        return True

    # Verify original byte
    if data[PATCH_OFFSET] != ORIGINAL_BYTE:
        print(f"ERROR: Expected byte 0x{ORIGINAL_BYTE:02X} at offset 0x{PATCH_OFFSET:X}, but found 0x{data[PATCH_OFFSET]:02X}")
        print("This might not be a Tibia 7.70 client or it's already modified.")
        return False

    # Apply patch
    print(f"Patching byte at offset 0x{PATCH_OFFSET:X}: 0x{ORIGINAL_BYTE:02X} -> 0x{PATCHED_BYTE:02X}")
    data[PATCH_OFFSET] = PATCHED_BYTE

    # Write back
    with open(client_path, 'wb') as f:
        f.write(data)

    print("Multiclient patch applied successfully!")
    print("You can now run multiple Tibia clients simultaneously.")
    return True

def main():
    if len(sys.argv) != 2:
        print("Tibia 7.70 Multiclient Patcher")
        print("Usage:")
        print(f"  {sys.argv[0]} /path/to/Tibia.exe")
        print("")
        print("Example:")
        print(f"  {sys.argv[0]} \"/home/user/.wine/drive_c/Program Files (x86)/Tibia/Tibia.exe\"")
        sys.exit(1)

    client_path = sys.argv[1]

    if not os.path.exists(client_path):
        print(f"ERROR: Tibia client not found at: {client_path}")
        sys.exit(1)

    print(f"Patching Tibia client: {client_path}")

    if patch_client(client_path):
        print("\nPatch completed successfully!")
    else:
        print("\nPatch failed!")
        sys.exit(1)

if __name__ == "__main__":
    main()