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

add_repos() {
	echo -e "${CYAN}=== Adding Repositories ===${NC}"

    if ask "Add RPM Fusion (Free & Non-Free)?" "Y"; then
        echo -e "${YELLOW}Installing RPM Fusion repositories...${NC}"
        dnf install -y \
            https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
            https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

        # Pulls in necessary AppStream metadata for the new repos
        dnf groupupdate core -y
        echo -e "${GREEN}RPM Fusion added successfully.${NC}"
    else
        echo "Skipping RPM Fusion."
    fi

    if ask "Add Terra Repository?" "Y"; then
        echo -e "${YELLOW}Adding Terra repository...${NC}"

	sudo dnf install --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release -y

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

    if ask "Install 'Standard' group?" "Y"; then
        echo -e "${YELLOW}Installing Standard group...${NC}"
        dnf group install -y "standard"
    fi

    if ask "Install 'NetworkManager Submodules'?" "Y"; then
        echo -e "${YELLOW}Installing NetworkManager Submodules...${NC}"
        # This provides VPN plugins (OpenVPN, WireGuard, etc.) and specific network protocols
        dnf group install -y "networkmanager-submodules"
    fi

    if ask "Install 'Hardware Support'?" "Y"; then
        echo -e "${YELLOW}Installing Hardware Support...${NC}"
        # Brings in necessary firmware, smartcard readers, and generic hardware tools
        dnf group install -y "hardware-support"
    fi

    if ask "Install 'Multimedia'?" "Y"; then
        echo -e "${YELLOW}Installing Multimedia...${NC}"
        # Since you added RPM Fusion earlier, this will automatically pull in
        # non-free codecs, gstreamer plugins, and hardware acceleration packages
        dnf group install -y "multimedia"
    fi

    if ask "Install 'Development Tools'?" "Y"; then
        echo -e "${YELLOW}Installing Development Tools...${NC}"
        # Pulls in gcc, make, automake, git, and compiling dependencies
        dnf group install -y "d-development"
    fi
}

install_core_tools() {
	echo -e "${CYAN}=== Installing Core System Tools ===${NC}"

    if ask "Install core CLI utilities (git, curl, wget, etc.)?" "Y"; then
        # Define the array of core packages
	
	ALL_PACKAGES=(
	    "${SYS_CORE[@]}"
	    "${APPEARANCE[@]}"
	    "${CLI_TOOLS[@]}"
	    "${SYS_SERVICES[@]}"
	    "${VIRTUALIZATION[@]}"
	)

	SYS_CORE=(
	    acpid
	    cmake
	    config-manager
	    dkms
	    dnf-plugins-core
	    gcc
	    kernel-devel-matched
	    kernel-headers
	    libglvnd-devel
	    libglvnd-glx
	    libglvnd-opengl
	    make
	    pkgconfig
	    power-profiles-daemon
	    supergfxctl
	)
	APPEARANCE=(
	    adw-gtk3-theme
	    bibata-cursor-theme
	    google-noto-color-emoji-fonts
	    jetbrainsmono-nerd-fonts
	    nerdfontssymbolsonly-nerd-fonts
	    nwg-look
	    qt5ct
    	    qt6ct
	    papirus-icon-theme
	)
	CLI_TOOLS=(
	    7zip
	    aria2
	    bat
	    btop
	    curl
	    dialog
	    eza
	    fastfetch
	    fd
	    ffmpeg
	    fish
	    fzf
	    gdu
	    git
	    grim
	    jq
	    nano
	    nmtui
	    pipx
	    poppler
	    python3-pip
	    rg
	    rsync
	    starship
	    slurp
	    tealdeer
	    tesseract
	    tesseract-langpack-eng
	    topgrade
	    vim
	    wget
	    yazi
	    yt-dlp
	    zoxide
	)
	SYS_SERVICES=(
	    gnome-disk-utility
	    gnome-keyring
	    gnome-keyring-pam
	    gnome-software
	    gocryptfs
	    gvfs
	    kde-cli-tools
	    lxmenu-data
	    pavucontrol
	    rofi
	    xarchiver
	    xdg-user-dirs
	    xdg-user-dirs-update
	)
	VIRTUALIZATION=(
	    libvirt
	    virt-install
	    virt-manager
	    virt-viewer
	)

        echo -e "${YELLOW}Installing core packages...${NC}"

        # Pass the entire array to dnf so it resolves dependencies in one go
        if  sudo dnf install -y "${ALL_PACKAGES[@]}"; then
            echo -e "${GREEN}Core tools installed successfully.${NC}"
        else
            echo -e "${RED}Error: Failed to install some core tools. Please check the output above.${NC}"
        fi
    else
        echo "Skipping core system tools."
    fi
}

install_gpu() {
	echo -e "${CYAN}=== Installing Graphics Drivers ===${NC}"

    # AMD
    if ask "Install AMD Drivers (Mesa/Vulkan/VAAPI)?" "N"; then
        echo -e "${YELLOW}Installing AMD packages...${NC}"
        # mesa-va-drivers is for hardware video acceleration, mesa-vulkan-drivers for gaming/Wayland
        if dnf install -y mesa-dri-drivers mesa-vulkan-drivers mesa-va-drivers mesa-vdpau-drivers rocm-opencl; then
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
	sudo dnf install -y supergfxctl
        
        # Enable and start the daemon so it works immediately
        sudo systemctl enable --now supergfxd.service
        
        echo -e "${GREEN}supergfxctl setup complete and service started.${NC}"
    else
        echo "Skipping supergfxctl installation."
    fi
}

install_apps() {
	echo -e "${CYAN}=== Installing Apps ===${NC}"
	choose_browser
	choose_file_manager

    # ---------------------------------------------------------
    # EDIT THESE ARRAYS TO ADD/REMOVE YOUR PREFERRED APPS
    # ---------------------------------------------------------
    local dnf_apps=(
        foot                  # Terminal emulator
        mpv                    # Video player
        feh                    # Image viewer
        easyeffects
        evince
        feh
        galculator
        geany
        localsend
        mpv
        onlyoffice-desktopeditors
        pcmanfm
        telegram-desktop
        )
    local flatpak_apps=(i
	com.bitwarden.desktop
	com.rtosta.zapzap
	io.ente.auth
	org.kde.drawy
    )
    # ---------------------------------------------------------

    if ask "Install GUI Apps via DNF?" "Y"; then
        echo -e "${YELLOW}Installing DNF apps...${NC}"
        dnf install -y "${dnf_apps[@]}"
        echo -e "${GREEN}DNF apps installed successfully.${NC}"
    else
        echo "Skipping DNF apps."
    fi

    if ask "Install GUI Apps via Flatpak?" "Y"; then

        # Failsafe: Ensure flatpak command exists just in case they skipped the Flatpak setup step earlier
        if ! command -v flatpak &> /dev/null; then
            echo -e "${RED}Flatpak is not installed. Attempting to install it now...${NC}"
	    # Call setup_flatpak. If it returns 1 (user says no), abort app install.
            setup_flatpak || {
                echo -e "${RED}Flatpak setup was aborted. Cannot install Flatpak apps.${NC}"
                return
            }
        fi

        echo -e "${YELLOW}Installing Flatpak apps...${NC}"
	flatpak install -y flathub "${flatpak_apps[@]}"
        echo -e "${GREEN}Flatpak apps installed successfully.${NC}"
    else
        echo "Skipping Flatpak apps."
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
                sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo 
                sudo dnf install -y brave-origin
                break
                ;;
            "Zen Browser")
                echo "Installing Zen Browser..."
                sudo dnf install -y zen-browser 
                break
                ;;
            "Firefox")
                echo "Installing Firefox..."
                sudo dnf install -y firefox
                break
                ;;
            "Helium Browser")
                echo "Installing Helium Browser..."
                sudo dnf install -y helium-browser-bin
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
                sudo dnf install -y "$choice"
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
}

install_hyprland() {
	echo -e "${CYAN}=== Installing Hyprland ===${NC}"

	if ask "Install core Hyprland compositor and XDG portals?" "Y"; then
        echo "Installing core Hyprland..."
        dnf copr enable lionheartp/Hyprland -y
        dnf install -y hyprland hyprland-guiutils xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
    fi

    if ask "Install and enable SDDM (Display Manager / Login Screen)?" "N"; then
        echo "Installing SDDM..."
        dnf install -y sddm
        # Enable it to start automatically on boot
        systemctl enable sddm.service
    else
        echo -e "${YELLOW}Skipping SDDM. You will need to log in via TTY and type 'Hyprland' to start your session.${NC}"
    fi

    echo -e "${GREEN}Hyprland setup complete.${NC}"
}

install_noctalia() {
	echo -e "${CYAN}=== Installing Noctalia ===${NC}"

	if ask "Install Noctalia (Unified Wayland Desktop Shell)?" "Y"; then
            sudo dnf install -y noctalia
        	echo -e "${GREEN}Noctalia setup complete.${NC}"
    	else
        	echo "Skipping Noctalia installation."
    fi
}

setup_dotfiles() {
	echo -e "${CYAN}=== Copying Dotfiles ===${NC}"

	if ask "Clone and deploy your dotfiles?" "Y"; then

        # 1. Identify the real user (since the script runs as root)
        local REAL_USER=${SUDO_USER:-$(whoami)}
        local REAL_HOME=$(eval echo ~$REAL_USER)

        # 2. Define repository URL (You can hardcode your repo here)
        local DEFAULT_REPO=""
        local REPO_URL

        read -p "Enter your dotfiles Git repo URL [${DEFAULT_REPO}]: " REPO_URL
        REPO_URL=${REPO_URL:-$DEFAULT_REPO}

        if [ -z "$REPO_URL" ]; then
            echo -e "${RED}No URL provided. Skipping dotfiles.${NC}"
            return
        fi

        local DOTFILES_DIR="${REAL_HOME}/dotfiles"

        # 3. Ensure git and stow are installed
        if ! command -v git &> /dev/null || ! command -v stow &> /dev/null; then
            echo -e "${YELLOW}Installing git and GNU stow...${NC}"
            dnf install -y git stow
        fi

        # 4. Clone the repository
        if [ -d "$DOTFILES_DIR" ]; then
            echo -e "${YELLOW}Directory $DOTFILES_DIR already exists.${NC}"
            if ask "Remove existing directory and re-clone?" "N"; then
                rm -rf "$DOTFILES_DIR"
                sudo -u "$REAL_USER" git clone "$REPO_URL" "$DOTFILES_DIR"
            else
                echo "Using existing repository. Pulling latest changes..."
                sudo -u "$REAL_USER" bash -c "cd $DOTFILES_DIR && git pull"
            fi
        else
            echo "Cloning dotfiles for user $REAL_USER..."
            sudo -u "$REAL_USER" git clone "$REPO_URL" "$DOTFILES_DIR"
        fi

        # 5. Deploy using GNU Stow
        if ask "Deploy dotfiles using GNU Stow?" "Y"; then
            echo -e "${YELLOW}Note: This will symlink folders from $DOTFILES_DIR to $REAL_HOME.${NC}"

            # Optional: Let the user specify which folders to stow, or stow everything.
            read -p "Enter stow folders (space separated, e.g., 'hypr waybar', or '.' for all): " STOW_PKGS

            if [ -n "$STOW_PKGS" ]; then
                pushd "$DOTFILES_DIR" > /dev/null || return

                if [ "$STOW_PKGS" = "." ]; then
                    echo "Stowing all directories..."
                    sudo -u "$REAL_USER" stow -t "$REAL_HOME" .
                else
                    for pkg in $STOW_PKGS; do
                        echo "Stowing $pkg..."
                        sudo -u "$REAL_USER" stow -t "$REAL_HOME" "$pkg"
                    done
                fi

                popd > /dev/null || return
                echo -e "${GREEN}Dotfiles deployed successfully!${NC}"
            else
                echo "No packages specified. Skipping stow."
            fi
        else
            echo -e "${YELLOW}Dotfiles cloned to $DOTFILES_DIR but not deployed.${NC}"
        fi
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
        ./install.sh

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
    ask "Step 10: Copy Dotfiles?" "Y" && setup_dotfiles
    ask "Step 11: Setup Bash & Starship?" "Y" && setup_shell
    ask "Step 12: Setup Snapper?" "Y" && setup_snapper
    
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
    echo "14. Setup Snapper"
    echo "0. Exit"
    echo -e "${GREEN}=======================================${NC}"
}

main() {
    # Run all system checks before allowing the script to proceed
    run_prechecks
    
    while true; do
        show_menu
        read -p "Select an option [0-12]: " choice
        
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
	    14) setup_snapper; pause ;;
            0) echo "Exiting..."; exit 0 ;;
            *) echo -e "${RED}Invalid option. Please try again.${NC}"; sleep 1 ;;
        esac
    done
}

# Execute main function
main
