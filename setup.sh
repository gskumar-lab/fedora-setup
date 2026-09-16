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

check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Please run this script with sudo or as root.${NC}"
        exit 1
    fi
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
    if ask "Configure custom DNS (e.g., Cloudflare/Quad9)?" "Y"; then
        # TODO: DNS Logic here
        echo "DNS configured."
    else
        echo "Skipping DNS."
    fi
}

add_repos() {
	echo -e "${CYAN}=== Adding Repositories ===${NC}"
    ask "Add RPM Fusion (Free & Non-Free)?" "Y" && {
        # TODO: RPM fusion logic
        echo "RPM Fusion added."
    }
    ask "Add Terra Repository?" "Y" && {
        # TODO: Terra logic
        echo "Terra added."
    }
}

setup_flatpak() {
	echo -e "${CYAN}=== Setting up Flatpak ===${NC}"
    ask "Install Flatpak and add Flathub remote?" "Y" && {
        # TODO: Flatpak logic
        echo "Flatpak setup complete."
    }
}

install_groups() {
	echo -e "${CYAN}=== Installing Package Groups ===${NC}"
    ask "Install 'Standard' group?" "Y" && echo "Installing Standard..."
    ask "Install 'NetworkManager Submodules'?" "Y" && echo "Installing NM Submodules..."
    ask "Install 'Hardware Support'?" "Y" && echo "Installing Hardware Support..."
    ask "Install 'Multimedia'?" "Y" && echo "Installing Multimedia..."
    ask "Install 'Development Tools'?" "Y" && echo "Installing Development Tools..."
    # TODO: Add actual dnf groupinstall commands above
}

install_core_tools() {
	echo -e "${CYAN}=== Installing Core System Tools ===${NC}"
    if ask "Install core CLI utilities (git, curl, wget, etc.)?" "Y"; then
        # TODO: Define and install CLI utilities
        echo "Core tools installed."
    fi
}

install_gpu() {
	echo -e "${CYAN}=== Installing Graphics Drivers ===${NC}"
    ask "Install AMD Drivers (Mesa/Vulkan)?" "N" && echo "Installing AMD..."
    ask "Install NVIDIA Drivers (Proprietary)?" "N" && echo "Installing NVIDIA..."
    ask "Install Intel Drivers?" "N" && echo "Installing Intel..."
    # TODO: Add actual DNF commands above
}

install_apps() {
	echo -e "${CYAN}=== Installing Apps ===${NC}"
    ask "Install GUI Apps via DNF?" "Y" && echo "Installing DNF apps..."
    ask "Install GUI Apps via Flatpak?" "Y" && echo "Installing Flatpak apps..."
    # TODO: Add actual app arrays and install loops
}

install_hyprland() {
	echo -e "${CYAN}=== Installing Hyprland ===${NC}"
    if ask "Install Hyprland and Wayland ecosystem?" "Y"; then
        # TODO: Hyprland logic
        echo "Hyprland setup complete."
    fi
}

install_noctalia() {
	echo -e "${CYAN}=== Installing Noctalia ===${NC}"
    if ask "Install and apply Noctalia theme?" "Y"; then
        # TODO: Noctalia clone/apply logic
        echo "Noctalia installed."
    fi
}

setup_dotfiles() {
	echo -e "${CYAN}=== Copying Dotfiles ===${NC}"
    if ask "Clone and deploy your dotfiles?" "Y"; then
        # TODO: Git clone and stow/cp logic
        echo "Dotfiles copied successfully."
    fi
}

setup_shell() {
	echo -e "${CYAN}=== Setting up Bash & Starship ===${NC}"
    ask "Install Starship prompt?" "Y" && echo "Installing Starship..."
    ask "Apply custom .bashrc configurations?" "Y" && echo "Configuring .bashrc..."
    # TODO: Shell logic
}

# ==========================================
# FULL SETUP
# ==========================================

full_setup() {
    echo -e "${YELLOW}Starting Full System Setup...${NC}"
    
    ask "Step 1: Change DNS?" "Y" && change_dns
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
    echo "0. Exit"
    echo -e "${GREEN}=======================================${NC}"
}

main() {
    check_sudo
    
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
            0) echo "Exiting..."; exit 0 ;;
            *) echo -e "${RED}Invalid option. Please try again.${NC}"; sleep 2 ;;
        esac
    done
}

# Execute main function
main
