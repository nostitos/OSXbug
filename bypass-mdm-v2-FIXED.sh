#!/bin/bash

# bypass-mdm-v2-FIXED.sh
# Fixed version that mounts the Data volume in Recovery Mode

# Define color codes
RED='\033[1;31m'
GRN='\033[1;32m'
BLU='\033[1;34m'
YEL='\033[1;33m'
PUR='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m'

# Error handling function
error_exit() {
	echo -e "${RED}ERROR: $1${NC}" >&2
	exit 1
}

# Warning function
warn() {
	echo -e "${YEL}WARNING: $1${NC}"
}

# Success function
success() {
	echo -e "${GRN}✓ $1${NC}"
}

# Info function
info() {
	echo -e "${BLU}ℹ $1${NC}"
}

# Variable to store the mounted data volume name
MOUNTED_DATA_VOL=""

# Function to mount data volume if not already mounted
mount_data_volume() {
    info "Checking if data volume needs to be mounted..." >&2
    
    # Check if Data volume is already mounted
    if [ -d "/Volumes/Data" ]; then
        info "Data volume already mounted" >&2
        MOUNTED_DATA_VOL="Data"
        return 0
    fi
    
    # Find the data volume identifier from diskutil
    local data_volume_id
    
    # Strategy 1: Look for "Data" APFS volume that's not the system
    data_volume_id=$(diskutil list | grep "APFS Volume" | grep -E "\sData\s" | awk '{print $NF}' | head -1)
    
    # Strategy 2: If not found, look for volume with Data in name
    if [ -z "$data_volume_id" ]; then
        data_volume_id=$(diskutil list | grep "APFS Volume" | grep "Data" | awk '{print $NF}' | head -1)
    fi
    
    if [ -n "$data_volume_id" ]; then
        info "Found data volume identifier: $data_volume_id" >&2
        info "Mounting data volume..." >&2
        
        if diskutil mount "$data_volume_id" >/dev/null 2>&1; then
            success "Data volume mounted successfully" >&2
            MOUNTED_DATA_VOL="Data"
            sleep 1
            return 0
        else
            warn "Standard mount failed, trying force mount..." >&2
            if diskutil mountDisk "$data_volume_id" >/dev/null 2>&1; then
                success "Data volume mounted with mountDisk" >&2
                MOUNTED_DATA_VOL="Data"
                sleep 1
                return 0
            fi
        fi
    fi
    
    warn "Could not automatically mount data volume" >&2
    return 1
}

# Function to detect system volumes with multiple fallback strategies
detect_volumes() {
	local system_vol=""
	local data_vol=""

	info "Detecting system volumes..." >&2

	# Strategy 1: Look for common macOS APFS volume patterns
	for vol in /Volumes/*; do
		if [ -d "$vol" ]; then
			vol_name=$(basename "$vol")

			# Check if this looks like a system volume (not Data, not recovery)
			if [[ ! "$vol_name" =~ "Data"$ ]] && [[ ! "$vol_name" =~ "Recovery" ]] && [ -d "$vol/System" ]; then
				system_vol="$vol_name"
				info "Found system volume: $system_vol" >&2
				break
			fi
		fi
	done

	# Strategy 2: If no system volume found, try looking for any volume with /System directory
	if [ -z "$system_vol" ]; then
		for vol in /Volumes/*; do
			if [ -d "$vol/System" ]; then
				system_vol=$(basename "$vol")
				warn "Using volume with /System directory: $system_vol" >&2
				break
			fi
		done
	fi

	# Strategy 3: Check for Data volume
	if [ -d "/Volumes/Data" ]; then
		data_vol="Data"
		info "Found data volume: $data_vol" >&2
	elif [ -n "$system_vol" ] && [ -d "/Volumes/$system_vol - Data" ]; then
		data_vol="$system_vol - Data"
		info "Found data volume: $data_vol" >&2
	else
		# Look for any volume ending with "Data"
		for vol in /Volumes/*Data; do
			if [ -d "$vol" ]; then
				data_vol=$(basename "$vol")
				warn "Found data volume: $data_vol" >&2
				break
			fi
		done
	fi
	
	# Strategy 4: Use the mounted data volume if we just mounted it
	if [ -z "$data_vol" ] && [ -n "$MOUNTED_DATA_VOL" ] && [ -d "/Volumes/$MOUNTED_DATA_VOL" ]; then
		data_vol="$MOUNTED_DATA_VOL"
		info "Using mounted data volume: $data_vol" >&2
	fi
	
	# Strategy 5: Look for any volume with dslocal directory (indicates data volume)
	if [ -z "$data_vol" ]; then
		for vol in /Volumes/*; do
			if [ -d "$vol" ]; then
				vol_name=$(basename "$vol")
				# Skip system volume, recovery volumes, and macOS Base System
				if [ "$vol_name" != "$system_vol" ] && [[ ! "$vol_name" =~ "Recovery" ]] && [[ ! "$vol_name" =~ "Preboot" ]] && [[ ! "$vol_name" =~ "VM" ]] && [[ ! "$vol_name" =~ "Base System" ]]; then
					# Check if this volume has the dslocal directory
					if [ -d "$vol/private/var/db/dslocal" ]; then
						data_vol="$vol_name"
						info "Found data volume by dslocal presence: $data_vol" >&2
						break
					fi
				fi
			fi
		done
	fi

	# Validate findings
	if [ -z "$system_vol" ]; then
		error_exit "Could not detect system volume. Please ensure you're running this in Recovery mode with a macOS installation present."
	fi

	if [ -z "$data_vol" ]; then
		error_exit "Could not detect data volume. Please ensure you're running this in Recovery mode with a macOS installation present."
	fi

	echo "$system_vol|$data_vol"
}

# Mount data volume first
mount_data_volume

# Detect volumes at startup
volume_info=$(detect_volumes)
system_volume=$(echo "$volume_info" | cut -d'|' -f1)
data_volume=$(echo "$volume_info" | cut -d'|' -f2)

# Display header
echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Bypass MDM By Assaf Dori (assafdori.com)   ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════╝${NC}"
echo ""
success "System Volume: $system_volume"
success "Data Volume: $data_volume"
echo ""

# Prompt user for choice
PS3='Please enter your choice: '
options=("Bypass MDM from Recovery" "Reboot & Exit")
select opt in "${options[@]}"; do
	case $opt in
	"Bypass MDM from Recovery")
		echo ""
		echo -e "${YEL}═══════════════════════════════════════${NC}"
		echo -e "${YEL}  Starting MDM Bypass Process${NC}"
		echo -e "${YEL}═══════════════════════════════════════${NC}"
		echo ""

		# Normalize data volume name if needed
		if [ "$data_volume" != "Data" ]; then
			info "Renaming data volume to 'Data' for consistency..."
			if diskutil rename "$data_volume" "Data" >/dev/null 2>&1; then
				success "Data volume renamed successfully"
				data_volume="Data"
			else
				warn "Could not rename data volume, continuing with: $data_volume"
			fi
		fi

		# Validate critical paths
		info "Validating system paths..."

		system_path="/Volumes/$system_volume"
		data_path="/Volumes/$data_volume"

		if [ ! -d "$system_path" ]; then
			error_exit "System volume path does not exist: $system_path"
		fi

		if [ ! -d "$data_path" ]; then
			error_exit "Data volume path does not exist: $data_path"
		fi

		dscl_path="$data_path/private/var/db/dslocal/nodes/Default"
		if [ ! -d "$dscl_path" ]; then
			error_exit "Directory Services path does not exist: $dscl_path"
		fi

		success "All system paths validated"
		echo ""

		# Create Temporary User
		echo -e "${CYAN}Creating Temporary Admin User${NC}"
		echo -e "${NC}Press Enter to use defaults (recommended)${NC}"

		# Get and validate real name
		read -p "Enter Temporary Fullname (Default is 'Apple'): " realName
		realName="${realName:=Apple}"

		# Get and validate username
		while true; do
			read -p "Enter Temporary Username (Default is 'Apple'): " username
			username="${username:=Apple}"
			
			# Check if username is empty
			if [ -z "$username" ]; then
				warn "Username cannot be empty"
				continue
			fi
			
			# Check length (1-31 characters for macOS)
			if [ ${#username} -gt 31 ]; then
				warn "Username too long (max 31 characters)"
				continue
			fi
			
			break
		done

		# Get and validate password
		while true; do
			read -p "Enter Temporary Password (Default is '1234'): " passw
			passw="${passw:=1234}"
			
			if [ ${#passw} -lt 4 ]; then
				warn "Password too short (minimum 4 characters recommended)"
				continue
			fi
			
			break
		done

		echo ""

		# Find available UID
		info "Checking for available UID..."
		available_uid="501"
		if dscl -f "$dscl_path" localhost -search /Local/Default/Users UniqueID 501 >/dev/null 2>&1; then
			available_uid="502"
			info "UID 501 is in use, using UID $available_uid instead"
		fi
		success "Using UID: $available_uid"
		echo ""

		# Create User with error handling
		info "Creating user account: $username"

		if ! dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" >/dev/null 2>&1; then
			error_exit "Failed to create user account"
		fi

		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UserShell "/bin/zsh" >/dev/null 2>&1 || warn "Failed to set user shell"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" RealName "$realName" >/dev/null 2>&1 || warn "Failed to set real name"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UniqueID "$available_uid" >/dev/null 2>&1 || warn "Failed to set UID"
		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" PrimaryGroupID "20" >/dev/null 2>&1 || warn "Failed to set GID"

		user_home="$data_path/Users/$username"
		if [ ! -d "$user_home" ]; then
			if mkdir -p "$user_home" >/dev/null 2>&1; then
				success "Created user home directory"
			else
				error_exit "Failed to create user home directory: $user_home"
			fi
		else
			warn "User home directory already exists: $user_home"
		fi

		dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" NFSHomeDirectory "/Users/$username" >/dev/null 2>&1 || warn "Failed to set home directory"

		if ! dscl -f "$dscl_path" localhost -passwd "/Local/Default/Users/$username" "$passw" >/dev/null 2>&1; then
			error_exit "Failed to set user password"
		fi

		if ! dscl -f "$dscl_path" localhost -append "/Local/Default/Groups/admin" GroupMembership "$username" >/dev/null 2>&1; then
			error_exit "Failed to add user to admin group"
		fi

		success "User account created successfully"
		echo ""

		# Block MDM domains
		info "Blocking MDM enrollment domains..."

		hosts_file="$system_path/etc/hosts"
		if [ ! -f "$hosts_file" ]; then
			warn "Hosts file does not exist, creating it"
			touch "$hosts_file" >/dev/null 2>&1 || error_exit "Failed to create hosts file"
		fi

		# Check if entries already exist to avoid duplicates
		grep -q "deviceenrollment.apple.com" "$hosts_file" 2>/dev/null || echo "0.0.0.0 deviceenrollment.apple.com" >> "$hosts_file"
		grep -q "mdmenrollment.apple.com" "$hosts_file" 2>/dev/null || echo "0.0.0.0 mdmenrollment.apple.com" >> "$hosts_file"
		grep -q "iprofiles.apple.com" "$hosts_file" 2>/dev/null || echo "0.0.0.0 iprofiles.apple.com" >> "$hosts_file"

		success "MDM domains blocked in hosts file"
		echo ""

		# Remove configuration profiles
		info "Configuring MDM bypass settings..."

		config_path="$system_path/var/db/ConfigurationProfiles/Settings"

		# Create config directory if it doesn't exist
		if [ ! -d "$config_path" ]; then
			if mkdir -p "$config_path" >/dev/null 2>&1; then
				success "Created configuration directory"
			else
				warn "Could not create configuration directory"
			fi
		fi

		# Mark setup as done
		touch "$data_path/private/var/db/.AppleSetupDone" >/dev/null 2>&1 && success "Marked setup as complete" || warn "Could not mark setup as complete"

		# Remove activation records
		rm -rf "$config_path/.cloudConfigHasActivationRecord" >/dev/null 2>&1 && success "Removed activation record" || info "No activation record to remove"
		rm -rf "$config_path/.cloudConfigRecordFound" >/dev/null 2>&1 && success "Removed cloud config record" || info "No cloud config record to remove"

		# Create bypass markers
		touch "$config_path/.cloudConfigProfileInstalled" >/dev/null 2>&1 && success "Created profile installed marker" || warn "Could not create profile marker"
		touch "$config_path/.cloudConfigRecordNotFound" >/dev/null 2>&1 && success "Created record not found marker" || warn "Could not create not found marker"

		echo ""
		echo -e "${GRN}╔═══════════════════════════════════════════════╗${NC}"
		echo -e "${GRN}║       MDM Bypass Completed Successfully!     ║${NC}"
		echo -e "${GRN}╚═══════════════════════════════════════════════╝${NC}"
		echo ""
		echo -e "${CYAN}Next steps:${NC}"
		echo -e "  1. Close this terminal window"
		echo -e "  2. Reboot your Mac"
		echo -e "  3. Login with username: ${YEL}$username${NC} and password: ${YEL}$passw${NC}"
		echo ""
		break
		;;
	"Reboot & Exit")
		echo ""
		info "Rebooting system..."
		reboot
		break
		;;
	*)
		echo -e "${RED}Invalid option $REPLY${NC}"
		;;
	esac
done
