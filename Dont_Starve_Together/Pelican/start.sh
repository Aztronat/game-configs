#!/bin/bash

# ==========================================
# Don't Starve Together - Two Shard Server Setup
# ==========================================
# This script starts a DST server with Master and Caves shards
# Designed for personal use with Pterodactyl game panel by Aztronat

# --- Pterodactyl Auto-Update ---
# Check the value of the AUTO_UPDATE variable from the panel.
# If it is set to "1", run the SteamCMD update.
if [ "${AUTO_UPDATE}" == "1" ]; then
    echo ">>> AUTO_UPDATE is set to 1, checking for game updates..."
    # Pterodactyl's SteamCMD is in a standard location.
    # The game files are in /home/container.
    /home/container/steamcmd/steamcmd.sh +force_install_dir /home/container +login anonymous +app_update 343050 validate +quit
    echo ">>> Game update check complete."
else
    echo ">>> AUTO_UPDATE is not set to 1, skipping update check."
fi
echo "" # Add a blank line for readability

# --- Configuration ---
CONTAINER_DIR="/home/container"
BIN_DIR="${CONTAINER_DIR}/bin64"
STORAGE_ROOT="${CONTAINER_DIR}/DoNotStarveTogether"
CLUSTER_NAME="MyDediServer"
MAX_PLAYERS="${MAX_PLAYERS:-20}"
CAVES_READY_FLAG="/tmp/caves_ready"
MASTER_READY_FLAG="/tmp/master_ready"

# Shard configurations: name, port, fifo, color
CAVES_PORT="11012"
CAVES_FIFO="/tmp/c"
CAVES_COLOR="38"

MASTER_PORT="11011"
MASTER_FIFO="/tmp/m"
MASTER_COLOR="35"

# --- Mod Patching ---  deprecated!
# Patch modmain.lua files after steamCMD and before server launch to fix server crash from mods.
#echo ">>> Checking and patching mod files..."
#
#MASTER_MOD_FILE="${CONTAINER_DIR}/ugc_mods/MyDediServer/Master/content/322330/1416161108/modmain.lua"
#CAVES_MOD_FILE="${CONTAINER_DIR}/ugc_mods/MyDediServer/Caves/content/322330/1416161108/modmain.lua"
#
#patch_mod_file() {
#    local MOD_FILE="$1"
#    
#    if [ -f "${MOD_FILE}" ]; then
        # Check if already patched to avoid "Successfully patched" message on every startup
        # We search for the NEW string. If found, we skip.
#        if grep -Fq "pos, self.inst))" "${MOD_FILE}"; then
#            echo "    [SKIP] File is already patched: ${MOD_FILE}"
#        else
#            echo "    [PATCH] Patching: ${MOD_FILE}"
            # Use sed to replace the specific function call
            # We look for the original pattern (ending in "pos))") and replace it with the new one (ending in "pos, self.inst))")
#            sed -i 's/(self\.can_cast_fn \~= nil and self\.can_cast_fn(doer, target, pos))/(self.can_cast_fn ~= nil and self.can_cast_fn(doer, target, pos, self.inst))/g' "${MOD_FILE}"
            
#            if [ $? -eq 0 ]; then
#                echo "    [SUCCESS] Patched: ${MOD_FILE}"
#            else
#                echo "    [ERROR] Failed to patch: ${MOD_FILE}"
#            fi
#        fi
#    else
#        echo "    [WARN] File not found (Mod may not be downloaded yet): ${MOD_FILE}"
#    fi
#}

# Patch both mod files
#patch_mod_file "${MASTER_MOD_FILE}"
#patch_mod_file "${CAVES_MOD_FILE}"
#echo ">>> Mod patching complete."
#echo ""

# --- Automatic Mod Setup Generation ---
# This section reads your Master shard's modoverrides.lua and generates
# the dedicated_server_mods_setup.lua file needed by the server.

MOD_OVERRIDES_SOURCE="${STORAGE_ROOT}/${CLUSTER_NAME}/Master/modoverrides.lua"
MOD_SETUP_TARGET="${CONTAINER_DIR}/mods/dedicated_server_mods_setup.lua"

echo ">>> Checking for modoverrides.lua to generate mod setup..."

if [ -f "${MOD_OVERRIDES_SOURCE}" ]; then
    echo "    Source file found: ${MOD_OVERRIDES_SOURCE}"
    echo "    Target file: ${MOD_SETUP_TARGET}"
    
    # Ensure the mods directory exists
    mkdir -p "${CONTAINER_DIR}/mods"
    
    # Extract all workshop IDs and create ServerModSetup calls
    grep -o '"workshop-[0-9]*"' "${MOD_OVERRIDES_SOURCE}" | \
    sed 's/"workshop-/ServerModSetup("/; s/"$/")/' > "${MOD_SETUP_TARGET}"
    
    if [ -s "${MOD_SETUP_TARGET}" ]; then
        echo "    Mod setup file generated successfully with the following mods:"
        cat "${MOD_SETUP_TARGET}"
    else
        echo "    WARNING: No workshop mods found in modoverrides.lua"
        echo "    Creating empty dedicated_server_mods_setup.lua"
        touch "${MOD_SETUP_TARGET}"
    fi
else
    echo "    WARNING: ${MOD_OVERRIDES_SOURCE} not found."
    echo "    Creating empty dedicated_server_mods_setup.lua to prevent crashes."
    mkdir -p "${CONTAINER_DIR}/mods"
    touch "${MOD_SETUP_TARGET}"
fi
echo "" # Add a blank line for readability

# --- Worldgenoverride Cleanup ---
for wg_file in \
    "${STORAGE_ROOT}/${CLUSTER_NAME}/Master/worldgenoverride.lua" \
    "${STORAGE_ROOT}/${CLUSTER_NAME}/Caves/worldgenoverride.lua"; do
    if [ -f "${wg_file}" ]; then
        before=$(cat "${wg_file}")
        sed -i '/="default"/d' "${wg_file}"
        after=$(cat "${wg_file}")
        if [ "${before}" != "${after}" ]; then
            shard_name=$(basename $(dirname "${wg_file}") | tr '[:lower:]' '[:upper:]')
            echo "    ${shard_name} worldgenoverride.lua DEFAULT ENTRIES REMOVED"
        fi
    fi
done

# --- leveldataoverride Cleanup ---
for ld_file in \
    "${STORAGE_ROOT}/${CLUSTER_NAME}/Master/leveldataoverride.lua" \
    "${STORAGE_ROOT}/${CLUSTER_NAME}/Caves/leveldataoverride.lua"; do
    if [ -f "${ld_file}" ]; then
        before=$(cat "${ld_file}")
        sed -i '/="default"/d' "${ld_file}"
        sed -i -E ':a;N;$!ba;s/,([[:space:]]*\})/\1/g' "${ld_file}"
        after=$(cat "${ld_file}")
        if [ "${before}" != "${after}" ]; then
            shard_name=$(basename $(dirname "${ld_file}") | tr '[:lower:]' '[:upper:]')
            echo "    ${shard_name} leveldataoverride.lua CLEANED"
        fi
    fi
done

# --- modoverrides.lua Validation ---
for shard in Master Caves; do
    mod_file="${STORAGE_ROOT}/${CLUSTER_NAME}/${shard}/modoverrides.lua"
    if [ -f "${mod_file}" ]; then
        before=$(cat "${mod_file}")
        sed -i -E ':a;N;$!ba;s/,([[:space:]]*\})/\1/g' "${mod_file}"
        after=$(cat "${mod_file}")
        if [ "${before}" != "${after}" ]; then
            echo "    ${shard} modoverrides.lua EXTRA END COMMA FIXED"
        fi
    fi
done

MASTER_MOD="${STORAGE_ROOT}/${CLUSTER_NAME}/Master/modoverrides.lua"
CAVES_MOD="${STORAGE_ROOT}/${CLUSTER_NAME}/Caves/modoverrides.lua"
if [ -f "${MASTER_MOD}" ] && [ -f "${CAVES_MOD}" ]; then
    if ! cmp -s "${MASTER_MOD}" "${CAVES_MOD}"; then
        echo ">>> WARNING /!\ THE modoverrides.lua OF MASTER AND CAVES ARE NOT IDENTICAL /!\ "
    fi
fi

# --- Cleanup Function ---
cleanup() {
    echo ">>> Shutting down server and cleaning up..."
    
    # Kill all child processes
    pkill -P $$ 2>/dev/null
    
    # Clean up FIFOs and flags
    rm -f "${CAVES_FIFO}" "${MASTER_FIFO}" "${CAVES_READY_FLAG}" "${MASTER_READY_FLAG}"
    
    echo ">>> Cleanup complete."
    exit 0
}

# --- Shard Start Functions ---
start_caves() {
    (
        cd "${BIN_DIR}" && \
        tail -f "${CAVES_FIFO}" 2>/dev/null | \
        nice -n -10 ./dontstarve_dedicated_server_nullrenderer_x64 \
            -bind_ip 0.0.0.0 \
            -port "${CAVES_PORT}" \
            -persistent_storage_root "${STORAGE_ROOT}" \
            -conf_dir . \
            -cluster "${CLUSTER_NAME}" \
            -players "${MAX_PLAYERS}" \
            -shard Caves 2>&1
    ) | stdbuf -oL tee >(grep -m1 "Sim paused" > /dev/null && touch "${CAVES_READY_FLAG}" && cat > /dev/null) \
      | stdbuf -oL sed "s/^/\x1b[38;5;${CAVES_COLOR}m[CAVES]\x1b[0m /" &
}

start_master() {
    (
        cd "${BIN_DIR}" && \
        tail -f "${MASTER_FIFO}" 2>/dev/null | \
        nice -n -10 ./dontstarve_dedicated_server_nullrenderer_x64 \
            -bind_ip 0.0.0.0 \
            -port "${MASTER_PORT}" \
            -persistent_storage_root "${STORAGE_ROOT}" \
            -conf_dir . \
            -cluster "${CLUSTER_NAME}" \
            -players "${MAX_PLAYERS}" \
            -shard Master 2>&1
    ) | stdbuf -oL tee >(grep -m1 "Sim paused" > /dev/null && touch "${MASTER_READY_FLAG}" && cat > /dev/null) \
      | stdbuf -oL sed "s/^/\x1b[38;5;${MASTER_COLOR}m[MASTER]\x1b[0m /" &
}

# --- Main Execution ---

# Set up trap for clean shutdown
trap cleanup EXIT SIGTERM SIGINT

echo ">>> Initializing Don't Starve Together server..."

# Remove old FIFOs and readiness flags
rm -f "${CAVES_FIFO}" "${MASTER_FIFO}" "${CAVES_READY_FLAG}" "${MASTER_READY_FLAG}"
mkfifo "${CAVES_FIFO}" "${MASTER_FIFO}"

# Initialize FIFOs
echo "" > "${CAVES_FIFO}" &
echo "" > "${MASTER_FIFO}" &

# Start Caves shard
echo ">>> Starting Caves shard on port ${CAVES_PORT}..."
start_caves

sleep 5

# Start Master shard
echo ">>> Starting Master shard on port ${MASTER_PORT}..."
start_master

echo ">>> All shards launched. Waiting for world generation..."

# Loop Tracking Variables
CAVES_ANNOUNCED=false
MASTER_ANNOUNCED=false
FUNCTIONS_SENT=false
BOTH_READY_TIME=0

# Custom Lua Functions
C_COUNT='c_count = function(...) local results = {} local grand_total = 0 for _, prefab in ipairs({...}) do local count = 0 for k, v in pairs(Ents) do if v.prefab == prefab and v.components.inventoryitem and v.components.inventoryitem.owner == nil then count = count + 1 end end table.insert(results, count .. " " .. prefab) grand_total = grand_total + count end print("There are " .. table.concat(results, ", ") .. " on the ground.") return grand_total end'

C_CLEANUP='c_cleanup = function(...) local results = {} local grand_total = 0 for _, prefab in ipairs({...}) do local count = 0 for k, v in pairs(Ents) do if v.prefab == prefab and v.components.inventoryitem and v.components.inventoryitem.owner == nil then v:Remove() count = count + 1 end end table.insert(results, count .. " " .. prefab) grand_total = grand_total + count end print("Cleaned up " .. table.concat(results, ", ") .. " off the ground.") return grand_total end'

# Main loop: handle stdin and monitor server processes
while read -t 1 -r line 2>/dev/null || true; do
    
    # Check if Caves finished loading
    if [ "${CAVES_ANNOUNCED}" = false ] && [ -f "${CAVES_READY_FLAG}" ]; then
        CAVES_ANNOUNCED=true
        echo ">> [CAVES] is live!"
    fi
    
    # Check if Master finished loading
    if [ "${MASTER_ANNOUNCED}" = false ] && [ -f "${MASTER_READY_FLAG}" ]; then
        MASTER_ANNOUNCED=true
        echo ">> [MASTER] is live!"
    fi

    # Announce when both shards are ready
    if [ "${CAVES_ANNOUNCED}" = true ] && [ "${MASTER_ANNOUNCED}" = true ] && [ "${FUNCTIONS_SENT}" = false ] && [ "${BOTH_READY_TIME}" = 0 ]; then
        echo ">>> Server is up and running!"
    fi

    # Trigger custom scripts 20 seconds after both are live
    if [ "${CAVES_ANNOUNCED}" = true ] && [ "${MASTER_ANNOUNCED}" = true ] && [ "${FUNCTIONS_SENT}" = false ]; then
        if [ "${BOTH_READY_TIME}" = 0 ]; then
            BOTH_READY_TIME=$(date +%s)
        fi
        now=$(date +%s)
        if [ $((now - BOTH_READY_TIME)) -ge 20 ]; then
            FUNCTIONS_SENT=true
            echo "${C_COUNT}" >> "${MASTER_FIFO}"
            echo "${C_CLEANUP}" >> "${MASTER_FIFO}"
            echo "${C_COUNT}" >> "${CAVES_FIFO}"
            echo "${C_CLEANUP}" >> "${CAVES_FIFO}"
            echo ">>> Successfully added custom console functions (c_count, c_cleanup)."
        fi
    fi

    # Handle standard console input
    if [ -n "$line" ]; then
        # Send input to Master first, then Caves
        echo "$line" >> "${MASTER_FIFO}" &
        sleep 0.1
        echo "$line" >> "${CAVES_FIFO}" &
    else
        # Check if any server process is still running
        if ! pidof dontstarve_dedicated_server_nullrenderer_x64 >/dev/null 2>&1; then
            echo ">>> No server processes detected. Exiting..."
            exit 0
        fi
    fi
done
