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

# ==========================================
# INSTALLATION FUNCTIONS
# ==========================================

change_dns() {
    echo -e "${CYAN}=== Changing DNS ===${NC}"
    # TODO: Modify systemd-resolved or NetworkManager settings
    echo "DNS configured successfully."
}

add_repos() {
    echo -e "${CYAN}=== Adding Repositories ===${NC}"
    # TODO: Install RPM Fusion (free/nonfree) and Terra repo
    echo "Repositories added successfully."
}

setup_flatpak() {
    echo -e "${CYAN}=== Setting up Flatpak ===${NC}"
    # TODO: Install flatpak, add flathub remote
    echo "Flatpak setup complete."
}

install_groups() {
    echo -e "${CYAN}=== Installing Package Groups ===${NC}"
    # TODO: dnf groupinstall standard, networkmanager-submodules, hardware-support, multimedia, development
    echo "Package groups installed."
}

install_core_tools() {
    echo -e "${CYAN}=== Installing Core System Tools ===${NC}"
    # TODO: Define and install CLI utilities (wget, git, curl, etc.)
    echo "Core tools installed."
}

install_gpu() {
    echo -e "${CYAN}=== Installing Graphics Drivers ===${NC}"
    # TODO: Detect GPU (AMD/Intel/NVIDIA) and install specific packages
    echo "Graphics drivers installed."
}

install_apps() {
    echo -e "${CYAN}=== Installing Apps ===${NC}"
    # TODO: Install DNF and Flatpak GUI applications
    echo "Apps installed."
}

install_hyprland() {
    echo -e "${CYAN}=== Installing Hyprland ===${NC}"
    # TODO: Install Hyprland and Wayland ecosystem (Waybar, Wofi, etc.)
    echo "Hyprland setup complete."
}

install_noctalia() {
    echo -e "${CYAN}=== Installing Noctalia ===${NC}"
    # TODO: Clone Noctalia repo and apply themes/configs
    echo "Noctalia installed."
}

setup_dotfiles() {
    echo -e "${CYAN}=== Copying Dotfiles ===${NC}"
    # TODO: Clone user dotfiles and symlink to ~/.config
    echo "Dotfiles copied successfully."
}

setup_shell() {
    echo -e "${CYAN}=== Setting up Bash & Starship ===${NC}"
    # TODO: Install Starship, append to .bashrc
    echo "Bash and Starship configured."
}

# ==========================================
# FULL SETUP
# ==========================================

full_setup() {
    echo -e "${YELLOW}Starting Full System Setup...${NC}"
    change_dns
    add_repos
    setup_flatpak
    install_groups
    install_core_tools
    install_gpu
    install_apps
    install_hyprland
    install_noctalia
    setup_dotfiles
    setup_shell
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
    echo "1. Full Setup (ALL)"
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
