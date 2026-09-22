#!/usr/bin/env bash

# Colors for formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ==========================================
# HELPER FUNCTIONS
# ==========================================

# PRE-CHECKS
run_prechecks() {
    echo -e "${CYAN}=== Running System Pre-checks ===${NC}"
    local HAS_ERROR=0

    # 1. Root / Sudo Check
    if [ "$EUID" -eq 0 ]; then
        echo -e "${GREEN}[OK] Running with root privileges.${NC}"
    else
        echo -e "${RED}[FAIL] This script must be run with sudo or as root.${NC}"
        HAS_ERROR=1
    fi

    # 2. OS Check (Ensure it's Fedora)
    if [ -f /etc/os-release ]; then
        # Source the os-release file to get variables like $ID and $NAME
        . /etc/os-release
        if [ "$ID" = "fedora" ]; then
            echo -e "${GREEN}[OK] OS detected: $NAME ($VERSION).${NC}"
        else
            echo -e "${RED}[FAIL] OS mismatch. This script is intended for Fedora, but detected $NAME.${NC}"
            HAS_ERROR=1
        fi
    else
        echo -e "${RED}[FAIL] Cannot determine OS. /etc/os-release is missing.${NC}"
        HAS_ERROR=1
    fi

    # 3. Network Connection Check (Ping Cloudflare's 1.1.1.1)
    if ping -c 1 -W 2 1.1.1.1 &> /dev/null; then
        echo -e "${GREEN}[OK] Internet connection verified.${NC}"
    else
        echo -e "${RED}[FAIL] No internet connection detected. A network connection is required.${NC}"
        HAS_ERROR=1
    fi

    # 4. Package Manager Check
    if command -v dnf &> /dev/null; then
        echo -e "${GREEN}[OK] DNF package manager found.${NC}"
    else
        echo -e "${RED}[FAIL] DNF not found!${NC}"
        HAS_ERROR=1
    fi

    # Halt script if any checks failed
    if [ $HAS_ERROR -eq 1 ]; then
        echo -e "${YELLOW}Pre-checks failed. Aborting script to prevent system damage.${NC}"
        exit 1
    fi

    echo -e "${GREEN}All pre-checks passed!${NC}"
    sleep 1
}

pause() {
    echo ""
    read -p "Press [Enter] to return to the menu..."
}

# The ask function takes a question and a default answer (Y or N)
ask() {
    local prompt default reply
    if [ "${2:-}" = "Y" ]; then
        prompt="Y/n"
        default=Y
    elif [ "${2:-}" = "N" ]; then
        prompt="y/N"
        default=N
    else
        prompt="y/n"
        default=
    fi

    while true; do
        echo -en "${YELLOW}$1 [$prompt] ${NC}"
        read -r reply
        # Default behavior on empty input
        if [ -z "$reply" ]; then
            reply=$default
        fi
        # Check answer
        case "$reply" in
            Y*|y*) return 0 ;;
            N*|n*) return 1 ;;
        esac
    done
}

# ==========================================
# INSTALLATION FUNCTIONS
# ==========================================

change_dns() {
	echo -e "${CYAN}=== Changing DNS ===${NC}"
    if ask "Configure custom global DNS (e.g., Cloudflare/Quad9)?" "Y"; then
        echo -e "\n${YELLOW}Select DNS Provider:${NC}"
        echo "1. Cloudflare (1.1.1.1, 1.0.0.1) [Fast & Private]"
        echo "2. Quad9 (9.9.9.9, 149.112.112.112) [Malware Blocking]"
        echo "3. Google (8.8.8.8, 8.8.4.4)"
        echo "4. Custom (Enter your own)"
        read -p "Enter choice [1-4]: " dns_choice

        case $dns_choice in
            1) DNS_SERVERS="1.1.1.1 1.0.0.1 2606:4700:4700::1111 2606:4700:4700::1001" ;;
            2) DNS_SERVERS="9.9.9.9 149.112.112.112 2620:fe::fe 2620:fe::9" ;;
            3) DNS_SERVERS="8.8.8.8 8.8.4.4 2001:4860:4860::8888 2001:4860:4860::8844" ;;
            4) read -p "Enter DNS IP addresses (space separated): " DNS_SERVERS ;;
            *) echo -e "${RED}Invalid choice. Skipping DNS setup.${NC}"; return ;;
        esac

        echo -e "${YELLOW}Applying DNS settings to systemd-resolved...${NC}"

        # Create a drop-in directory so updates don't overwrite our custom config
        mkdir -p /etc/systemd/resolved.conf.d

        # Write the configuration with Opportunistic DNS over TLS enabled
        cat <<EOF > /etc/systemd/resolved.conf.d/custom-dns.conf
[Resolve]
DNS=$DNS_SERVERS
DNSOverTLS=opportunistic
EOF

        # Restart the daemon to apply changes immediately
        systemctl restart systemd-resolved

        echo -e "${GREEN}DNS configured successfully! Current active servers:${NC}"
        resolvectl status | grep -E "DNS Servers" -A 2
    else
        echo "Skipping DNS."
    fi
}

setup_dnf_config() {
    echo -e "${CYAN}=== Configuring Sane DNF Defaults ===${NC}"
    
    if ask "Apply optimized DNF settings (faster downloads, fastest mirror, default yes)?" "Y"; then
        local DNF_CONF="/etc/dnf/dnf.conf"
        
        # 1. Backup the original config
        if [ ! -f "${DNF_CONF}.backup" ]; then
            cp "$DNF_CONF" "${DNF_CONF}.backup"
            echo "Created backup of $DNF_CONF"
        fi

        # 2. Define our sane defaults
        # max_parallel_downloads: Speeds up fetching packages
        # fastestmirror: Automatically connects to the lowest latency servers
        # defaultyes: Assumes 'y' for all DNF prompts automatically
        declare -A DNF_SETTINGS=(
            ["max_parallel_downloads"]="10"
            ["fastestmirror"]="True"
            ["defaultyes"]="True"
        )

        # 3. Apply settings safely
        for key in "${!DNF_SETTINGS[@]}"; do
            local value="${DNF_SETTINGS[$key]}"
            
            # If the setting already exists, modify it. Otherwise, append it.
            if grep -q "^${key}=" "$DNF_CONF"; then
                sed -i "s/^${key}=.*/${key}=${value}/" "$DNF_CONF"
            else
                echo "${key}=${value}" >> "$DNF_CONF"
            fi
        done

        echo -e "${GREEN}DNF configuration optimized!${NC}"
    else
        echo "Skipping DNF configuration."
    fi
}

add_repos() {
	echo -e "${CYAN}=== Adding Repositories ===${NC}"

	dnf install dnf-plugins-core -y

    if ask "Add RPM Fusion (Free & Non-Free)?" "Y"; then
        echo -e "${YELLOW}Installing RPM Fusion repositories...${NC}"
        dnf install -y \
            https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
            https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

        # Pulls in necessary updates from the new repos
        dnf upgrade --refresh -y
        echo -e "${GREEN}RPM Fusion added successfully.${NC}"
    else
        echo "Skipping RPM Fusion."
    fi

    if ask "Add Terra Repository?" "Y"; then
        echo -e "${YELLOW}Adding Terra repository...${NC}"

		dnf install --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release -y

        # The safest way across both DNF4 (F40) and DNF5 (F41+) is dropping the .repo file directly
        #curl -sLo /etc/yum.repos.d/terra.repo https://terra.fyralabs.com/terra.repo

        # Import the GPG key for Terra to prevent confirmation prompts later
        #rpm --import https://terra.fyralabs.com/key.pub
        
	echo -e "${GREEN}Terra repository added successfully.${NC}"
    else
        echo "Skipping Terra."
    fi

    # Refresh DNF cache so subsequent script steps can access the new packages
    echo -e "${YELLOW}Refreshing DNF cache...${NC}"
    dnf makecache
}

setup_flatpak() {
	echo -e "${CYAN}=== Setting up Flatpak ===${NC}"
    if ask "Install Flatpak and add Flathub remote?" "Y"; then
        echo -e "${YELLOW}Installing Flatpak...${NC}"
        dnf install -y flatpak

        echo -e "${YELLOW}Adding Flathub repository...${NC}"
        # --if-not-exists prevents the command from failing if Flathub is already configured
        flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

        echo -e "${GREEN}Flatpak setup complete.${NC}"
    else
        echo "Skipping Flatpak setup."
    fi
}

install_groups() {
    echo -e "${CYAN}=== Installing Package Groups ===${NC}"

    if ask "Install 'NetworkManager Submodules'?" "Y"; then
        echo -e "${YELLOW}Installing NetworkManager Submodules...${NC}"
        dnf group install -y "networkmanager-submodules"
    fi

    if ask "Install 'Hardware Support'?" "Y"; then
        echo -e "${YELLOW}Installing Hardware Support...${NC}"
        # Brings in necessary firmware, smartcard readers, and generic hardware tools
        dnf group install -y "hardware-support"
    fi

    if ask "Install 'Multimedia'?" "Y"; then
        echo -e "${YELLOW}Installing Multimedia...${NC}"
    	dnf install ffmpeg --allowerasing -y
        dnf group install -y "multimedia"
    fi

    if ask "Install 'Essential Fonts'?" "Y"; then
        echo -e "${YELLOW}Installing Fonts...${NC}"
        dnf install -y google-noto-color-emoji-fonts google-noto-sans-fonts google-noto-emoji-fonts google-noto-sans-mono-fonts jetbrainsmono-nerd-fonts nerdfontssymbolsonly-nerd-fonts
    fi
}

install_core_tools() {
    printf "%b\n" "${CYAN}=== Installing Core System Tools ===${NC}"

    if ask "Install core tools ?" "Y"; then
        
        printf "%b\n" "${YELLOW}Installing core packages...${NC}"

        # Define the corrected package list as a multi-line string
        ALL_PACKAGES=(
            7zip 
            acpid adw-gtk3-theme amd-ucode-firmware aria2
            bat bash-completion bibata-cursor-theme bind-utils btop btrfs-progs brightnessctl
            cmake curl chrony
            dbus dialog dosfstools dkms
            exfatprogs eza
            fastfetch fd-find foot fzf
            gcc gdu git gnome-keyring gnome-keyring-pam gocryptfs grim gvfs
            jq
            kde-cli-tools kernel-devel-matched kernel-headers
            libglvnd-devel libglvnd-glx libglvnd-opengl libvirt lxmenu-data
            make microcode_ctl
            nano NetworkManager-tui ntfs-3g
            papirus-icon-theme pavucontrol pciutils pipx pkgconfig poppler power-profiles-daemon python3-pip polkit-gnome
            ripgrep rofi rsync
            slurp stow sudo systemd-udev
            tar tealdeer tesseract tesseract-langpack-eng topgrade
            vim virt-install virt-manager virt-viewer
            unzip usbutils
            wget wget2-wget
            xdg-user-dirs xorg-x11-server-Xwayland
            yazi yt-dlp
            zip zoxide
        )

        # Execute without quotes around $ALL_PACKAGES to utilize standard word splitting
        if dnf install -y --skip-unavailable "${ALL_PACKAGES[@]}"; then
            printf "%b\n" "${GREEN}Core tools installed successfully.${NC}"
        else
            printf "%b\n" "${RED}Error: Failed to install some core tools. Please check the output above.${NC}"
        fi
    else
        printf "%s\n" "Skipping core system tools."
    fi
}

install_gpu() {
	echo -e "${CYAN}=== Installing Graphics Drivers ===${NC}"

    # AMD
    if ask "Install AMD Drivers (Mesa/Vulkan/VAAPI)?" "N"; then
        echo -e "${YELLOW}Installing AMD packages...${NC}"
        # mesa-va-drivers is for hardware video acceleration, mesa-vulkan-drivers for gaming/Wayland
        if dnf install -y mesa-dri-drivers mesa-vulkan-drivers mesa-va-drivers rocm-opencl; then
            echo -e "${GREEN}AMD drivers installed successfully.${NC}"
        else
            echo -e "${RED}Error installing AMD drivers.${NC}"
        fi
    fi

    # NVIDIA
    if ask "Install NVIDIA Drivers (Proprietary)? Requires RPM Fusion." "N"; then
        echo -e "${YELLOW}Installing NVIDIA packages...${NC}"
        # akmod-nvidia builds the kernel module automatically
        if dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda; then
            echo -e "${GREEN}NVIDIA drivers installed successfully.${NC}"
            echo -e "${YELLOW}WARNING: You may need to wait a few minutes before rebooting so 'akmods' can build the kernel module in the background.${NC}"
            echo -e "${YELLOW}NOTE: For Hyprland, ensure 'nvidia-drm.modeset=1' is in your kernel parameters.${NC}"
        else
            echo -e "${RED}Error installing NVIDIA drivers.${NC}"
        fi
    fi

    # INTEL
    if ask "Install Intel Drivers (Mesa/Vulkan/Media)?" "N"; then
        echo -e "${YELLOW}Installing Intel packages...${NC}"
        # intel-media-driver is for Broadwell (Gen8) and newer hardware acceleration
        # libva-intel-driver is a fallback for older Intel hardware
        if dnf install -y mesa-dri-drivers mesa-vulkan-drivers intel-media-driver libva-intel-driver; then
            echo -e "${GREEN}Intel drivers installed successfully.${NC}"
        else
            echo -e "${RED}Error installing Intel drivers.${NC}"
        fi
    fi

    install_supergfxctl
}

install_supergfxctl() {
    echo -e "${CYAN}=== Installing supergfxctl ===${NC}"

    if ask "Install supergfxctl (Graphics switching tool, recommended for hybrid GPUs/ASUS laptops)?" "Y"; then
        dnf copr enable lukenukem/asus-linux -y
	    dnf install -y supergfxctl
        
        # Enable and start the daemon so it works immediately
        systemctl enable --now supergfxd.service
        
        echo -e "${GREEN}supergfxctl setup complete and service started.${NC}"
    else
        echo "Skipping supergfxctl installation."
    fi
}

install_apps() {
    printf "%b\n" "${CYAN}=== Installing Apps ===${NC}"
    choose_browser
    choose_file_manager

	# PREFERRED APPS
	dnf_apps=(
        easyeffects evince
        feh
        galculator geany gnome-disk-utility gnome-software
        localsend
        mpv
        nwg-look
        onlyoffice-desktopeditors
        qt5ct qt6ct
        telegram-desktop
        xarchiver
    )

    if ask "Install GUI Apps via DNF?" "Y"; then
        printf "%b\n" "${YELLOW}Installing DNF apps...${NC}"
   
        # Check if the installation command succeeds
        if dnf install -y --skip-unavailable "${dnf_apps[@]}"; then
            printf "%b\n" "${GREEN}DNF apps installed successfully.${NC}"
        else
            printf "%b\n" "${RED}Error: Failed to install some DNF apps. Please check the output above.${NC}"
        fi
    else
        printf "%s\n" "Skipping DNF apps."
    fi

	flatpak_apps=(
        com.bitwarden.desktop
        com.rtosta.zapzap
        io.ente.auth
        org.kde.drawy
    )

    if ask "Install GUI Apps via Flatpak?" "Y"; then
        # Failsafe: Ensure flatpak command exists just in case they skipped the Flatpak setup step earlier
        if ! command -v flatpak > /dev/null 2>&1; then
            printf "%b\n" "${RED}Flatpak is not installed. Attempting to install it now...${NC}"
            # Call setup_flatpak. If it returns 1 (user says no), abort app install.
            setup_flatpak || {
                printf "%b\n" "${RED}Flatpak setup was aborted. Cannot install Flatpak apps.${NC}"
                return 1
            }
        fi

        printf "%b\n" "${YELLOW}Installing Flatpak apps...${NC}"
		if flatpak install -y flathub "${flatpak_apps[@]}"; then
            printf "%b\n" "${GREEN}Flatpak apps installed successfully.${NC}"
        else
            printf "%b\n" "${RED}Error: Failed to install some Flatpak apps. Please check the output above.${NC}"
        fi
    else
        printf "%s\n" "Skipping Flatpak apps."
    fi
}

choose_browser() {
    echo -e "\n=== Browser Selection ==="
    echo "Which browser would you like to install?"
    
    # Custom prompt for the select menu
    PS3="Enter the number of your choice (1-5): "
    
    # Define the options
    options=("Brave (brave-origin)" "Zen Browser" "Firefox" "Helium Browser" "Skip")
    
    select opt in "${options[@]}"; do
        case $opt in
            "Brave (brave-origin)")
                echo "Installing Brave..."
                dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo 
                dnf install -y brave-origin
                break
                ;;
            "Zen Browser")
                echo "Installing Zen Browser..."
                dnf install -y zen-browser 
                break
                ;;
            "Firefox")
                echo "Installing Firefox..."
                dnf install -y firefox
                break
                ;;
            "Helium Browser")
                echo "Installing Helium Browser..."
                dnf install -y helium-browser-bin
                break
                ;;
            "Skip")
                echo "Skipping browser installation."
                break
                ;;
            *) 
                echo "Invalid option: $REPLY. Please choose a number between 1 and 5."
                ;;
        esac
    done
}

choose_file_manager() {
    echo "Which file manager would you like to install?"

    # Customizes the prompt string for the select menu
    PS3="Enter the number of your choice (1-5): "

    # Define the options
    options=("dolphin" "pcmanfm" "thunar" "Skip")

    select choice in "${options[@]}"; do
        case $choice in
            "dolphin"|"pcmanfm"|"thunar")
                echo "Installing $choice..."
                dnf install -y "$choice"
                break
                ;;
            "Skip")
                echo "Skipping file manager installation."
                break
                ;;
            *)
                echo "Invalid option: $REPLY. Please choose a number between 1 and 5."
                ;;
        esac
    done
    xdg-user-dirs-update
}

install_hyprland() {
	echo -e "${CYAN}=== Installing Hyprland ===${NC}"

	if ask "Install core Hyprland compositor and XDG portals?" "Y"; then
        echo "Installing core Hyprland..."
        dnf copr enable lionheartp/Hyprland -y
        dnf install -y hyprland hyprland-guiutils xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
    fi

	echo "Configuring SELinux to Permissive mode..."
	# Set current session to permissive
	setenforce 0 || echo "Warning: Could not set active SELinux enforcement."

	# Make permissive mode persistent across reboots
	if [ -f /etc/selinux/config ]; then
	  sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
	  echo "SELinux configuration updated to permissive in /etc/selinux/config."
	else
	  echo "Warning: /etc/selinux/config not found. SELinux might not be installed."
	fi

	echo "Disabling existing graphical display managers..."
	# Disable common display managers to avoid conflicts
	systemctl disable gdm.service 2>/dev/null || true
	systemctl disable sddm.service 2>/dev/null || true
	systemctl disable lightdm.service 2>/dev/null || true

    if ask "Install and enable LY (Display Manager / Login Screen)?" "Y"; then
        echo "Installing LY..."
        dnf install -y ly
        # Enable it to start automatically on boot
        systemctl enable ly@tty2.service
    else
        echo -e "${YELLOW}Skipping LY. You will need to log in via TTY and type 'start-hyprland' to start your session.${NC}"
    fi

    echo -e "${GREEN}Hyprland setup complete.${NC}"
}

install_noctalia() {
	echo -e "${CYAN}=== Installing Noctalia ===${NC}"

	if ask "Install Noctalia (Unified Wayland Desktop Shell)?" "Y"; then
            dnf install -y noctalia
        	echo -e "${GREEN}Noctalia setup complete.${NC}"
    	else
        	echo "Skipping Noctalia installation."
    fi
}

setup_cloudflare_warp() {
    echo -e "${CYAN}=== Setting up Cloudflare WARP ===${NC}"
    
    if ask "Install and configure Cloudflare WARP?" "Y"; then
        echo -e "${YELLOW}Adding Cloudflare WARP repository...${NC}"
        # Sudo is omitted here since the script already runs as root
        curl -fsSl https://pkg.cloudflareclient.com/cloudflare-warp-ascii.repo | tee /etc/yum.repos.d/cloudflare-warp.repo
        
        echo -e "${YELLOW}Updating package cache and installing WARP...${NC}"
        dnf makecache
        dnf install cloudflare-warp -y

        echo -e "${YELLOW}Disabling WARP services...${NC}"
        # Disable the system-wide service
        systemctl disable --now warp-svc
        
        # Disable the user-specific service safely (targeting the actual user, not root)
        local REAL_USER=${SUDO_USER:-$(whoami)}
        if [ "$REAL_USER" != "root" ]; then
            local USER_UID=$(id -u "$REAL_USER")
            # We must set XDG_RUNTIME_DIR to interact with the user's systemd session
            sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$USER_UID" systemctl --user disable --now warp-desktop-svc
            echo "Disabled warp-desktop-svc for user: $REAL_USER"
        else
            # Fallback if somehow run as pure root without sudo
            systemctl --user disable --now warp-desktop-svc
        fi

        echo -e "${GREEN}Cloudflare WARP installed and services disabled!${NC}"
    else
        echo "Skipping Cloudflare WARP setup."
    fi
}

setup_dotfiles() {
    echo -e "${CYAN}=== Copying Dotfiles ===${NC}"

    if ask "Clone and deploy your dotfiles?" "Y"; then
        # 1. Identify the real user
        local REAL_USER=${SUDO_USER:-$(whoami)}
        local REAL_HOME=$(eval echo ~$REAL_USER)

        # 2. Define repository URL
        local DEFAULT_REPO="https://github.com/gskumar-lab/dotfiles.git"
        local REPO_URL
        read -p "Enter your dotfiles Git repo URL [${DEFAULT_REPO}]: " REPO_URL
        REPO_URL=${REPO_URL:-$DEFAULT_REPO}

        if [ -z "$REPO_URL" ]; then
            echo -e "${RED}No URL provided. Skipping dotfiles.${NC}"
            return
        fi

        # 3. Clone to a TEMPORARY directory
        local TMP_DIR="/tmp/dotfiles_deploy_$$"
        echo "Cloning dotfiles..."
        git clone "$REPO_URL" "$TMP_DIR"

        # 4. Deploy via hard copy from the 'home' folder
        if ask "Deploy dotfiles to $REAL_HOME?" "Y"; then
            
            # Verify the 'home' folder actually exists in the cloned repo
            if [ -d "$TMP_DIR/home" ]; then
                echo -e "${YELLOW}Copying files permanently to $REAL_HOME...${NC}"

                # The "/." at the end ensures we copy the CONTENTS of the home folder, 
                # not the folder itself, including hidden files.
                sudo -u "$REAL_USER" cp -a "$TMP_DIR/home/." "$REAL_HOME/"

                echo -e "${GREEN}Dotfiles deployed successfully!${NC}"
            else
                echo -e "${RED}Error: 'home' directory not found in the repository!${NC}"
            fi

        else
            echo -e "${YELLOW}Deployment cancelled.${NC}"
        fi

        # 5. Clean up the temporary repository to leave no trace
        rm -rf "$TMP_DIR"
    fi
}

setup_shell() {
	echo -e "${CYAN}=== Setting up Bash & Starship ===${NC}"

	# Detect the real user running sudo, and their home directory
    local REAL_USER=${SUDO_USER:-$(whoami)}
    local USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

    if ask "Install Starship prompt?" "Y"; then
        echo -e "${YELLOW}Installing Starship...${NC}"
        # Fedora has Starship in its official repositories
        dnf install -y starship
    fi

    if ask "Apply custom .bashrc configurations?" "Y"; then
        echo -e "${YELLOW}Configuring .bashrc for $REAL_USER...${NC}"

        local BASHRC_PATH="$USER_HOME/.bashrc"

        # 1. Backup the existing .bashrc just in case
        if [ -f "$BASHRC_PATH" ]; then
            cp "$BASHRC_PATH" "${BASHRC_PATH}.backup_$(date +%s)"
            echo "Created backup of .bashrc"
        fi

        # 2. Append Starship init if it doesn't already exist
        if ! grep -q 'starship init bash' "$BASHRC_PATH"; then
            echo -e '\n# Initialize Starship Prompt\neval "$(starship init bash)"' >> "$BASHRC_PATH"
            echo "Added Starship to .bashrc"
        fi

        # 3. Add custom aliases (Add any others you want here)
        if ! grep -q 'alias ls=' "$BASHRC_PATH"; then
            cat << 'EOF' >> "$BASHRC_PATH"

# Custom Aliases
alias ls='ls --color=auto'
alias ll='ls -lha'
alias grep='grep --color=auto'
EOF
            echo "Added custom aliases to .bashrc"
        fi

        # 4. Ensure the real user actually owns their .bashrc (fixes root permission issues)
        chown "$REAL_USER":"$REAL_USER" "$BASHRC_PATH"

        echo -e "${GREEN}Bash configurations applied successfully!${NC}"
    fi
}

setup_snapper() {
    echo -e "${CYAN}=== Setting up Snapper ===${NC}"

    if ask "Install and configure Snapper for BTRFS snapshots?" "Y"; then
        echo -e "${YELLOW}Cloning and running Snapper setup...${NC}"
        
        # Create a temporary directory to keep the workspace clean
        local SNAPPER_DIR=$(mktemp -d)
        pushd "$SNAPPER_DIR" > /dev/null || return

        # User's setup commands
        git clone https://github.com/SysGuides/sysguides-snapper-fedora .
        chmod +x install.sh

		# 1. Identify the real user who ran the sudo command
        local REAL_USER=${SUDO_USER:-$(whoami)}

        # 2. Change ownership of the temp directory so the normal user has permissions
        chown -R "$REAL_USER":"$REAL_USER" "$SNAPPER_DIR"

        # 3. Execute the script as the normal user
        sudo -u "$REAL_USER" ./install.sh

        popd > /dev/null || return
        
        # Cleanup temporary directory
        rm -rf "$SNAPPER_DIR"
        
        echo -e "${GREEN}Snapper setup script execution complete.${NC}"
    else
        echo "Skipping Snapper setup."
    fi
}

# ==========================================
# FULL SETUP
# ==========================================

full_setup() {
    echo -e "${YELLOW}Starting Full System Setup...${NC}"
    
    ask "Step 1: Change DNS?" "Y" && change_dns
    ask "Step 1.5: Optimize DNF config?" "Y" && setup_dnf_config
    ask "Step 2: Add Repositories?" "Y" && add_repos
    ask "Step 3: Setup Flatpak?" "Y" && setup_flatpak
    ask "Step 4: Install Package Groups?" "Y" && install_groups
    ask "Step 5: Install Core System Tools?" "Y" && install_core_tools
    ask "Step 6: Install Graphics Drivers?" "Y" && install_gpu
    ask "Step 7: Install Apps?" "Y" && install_apps
    ask "Step 8: Install Hyprland?" "Y" && install_hyprland
    ask "Step 9: Install Noctalia?" "Y" && install_noctalia
    ask "Step 10: Setup Cloudflare WARP" "Y" && setup_cloudflare_warp
    ask "Step 11: Copy Dotfiles?" "Y" && setup_dotfiles
    ask "Step 12: Setup Bash & Starship?" "Y" && setup_shell
    ask "Step 13: Setup Snapper?" "Y" && setup_snapper

    echo "Cleanup..."
    dnf autoremove -y
    dnf clean all
    
    echo -e "${GREEN}=== Full Setup Complete! Please Reboot. ===${NC}"
}

# ==========================================
# MAIN MENU
# ==========================================

show_menu() {
    clear
    echo -e "${GREEN}=======================================${NC}"
    echo -e "${GREEN}    Fedora Minimal Post-Install        ${NC}"
    echo -e "${GREEN}=======================================${NC}"
    echo "1. Full Setup (Interactive)"
    echo "2. Change DNS"
    echo "3. Add Repos (RPM Fusion, Terra)"
    echo "4. Setup Flatpak & Flathub"
    echo "5. Install Package Groups"
    echo "6. Install Core System Tools"
    echo "7. Install Graphics Drivers"
    echo "8. Install Apps"
    echo "9. Install Hyprland"
    echo "10. Install Noctalia"
    echo "11. Copy Dotfiles"
    echo "12. Setup Bash + Starship"
    echo "13. Setup Sane DNF Config"
    echo "14. Setup Cloudflare WARP"
    echo "15. Setup Snapper"
    echo "0. Exit"
    echo -e "${GREEN}=======================================${NC}"
}

main() {
    # Run all system checks before allowing the script to proceed
    run_prechecks
    
    while true; do
        show_menu
        read -p "Select an option [0-14]: " choice
        
        case $choice in
            1) full_setup; pause ;;
            2) change_dns; pause ;;
            3) add_repos; pause ;;
            4) setup_flatpak; pause ;;
            5) install_groups; pause ;;
            6) install_core_tools; pause ;;
            7) install_gpu; pause ;;
            8) install_apps; pause ;;
            9) install_hyprland; pause ;;
            10) install_noctalia; pause ;;
            11) setup_dotfiles; pause ;;
            12) setup_shell; pause ;;
	    13) setup_dnf_config; pause ;;
	    14) setup_cloudflare_warp; pause ;;
	    15) setup_snapper; pause ;;
            0) echo "Exiting..."; exit 0 ;;
            *) echo -e "${RED}Invalid option. Please try again.${NC}"; sleep 1 ;;
        esac
    done
}

# Execute main function
main
