#!/usr/bin/env bash

# tmot's configs
# GNU Stow should be installed. Run this from the directory that the script
# lives in.

if [ "$EUID" -eq 0 ]; then
    echo "Error: Do not run this script with sudo — it invokes sudo internally only for apt."
    exit 1
fi

# 0. Parse arguments
ACTION="-R"
ACTION_WORD="Stowing"

for arg in "$@"; do
    case $arg in
        -D)
            ACTION="-D"
            ACTION_WORD="Unstowing"
            ;;
        -h|--help)
            echo "Usage: $0 [-D]"
            echo "  -D    Unstow (delete symlinks) for all packages"
            echo "  -h, --help    Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Usage: $0 [-D]"
            exit 1
            ;;
    esac
done

# Install core apt packages (stow, tmux, git, pipx), tldr via pipx, and TPM
if [ "$ACTION" = "-R" ]; then
    APT_PKGS=()
    command -v stow &> /dev/null || APT_PKGS+=(stow)
    command -v tmux &> /dev/null || APT_PKGS+=(tmux)
    command -v git  &> /dev/null || APT_PKGS+=(git)
    command -v pipx &> /dev/null || APT_PKGS+=(pipx)

    if [ ${#APT_PKGS[@]} -gt 0 ]; then
        echo "Installing missing apt packages: ${APT_PKGS[*]}..."
        # Assuming Ubuntu/Debian; change to 'brew install' or 'pacman -S' if needed
        sudo apt update && sudo apt install -y "${APT_PKGS[@]}"
    fi

    if command -v pipx &> /dev/null && ! command -v tldr &> /dev/null && [ ! -x "$HOME/.local/bin/tldr" ]; then
        echo "Installing tldr via pipx..."
        pipx install tldr
    fi

    TPM_DIR="$HOME/.tmux/plugins/tpm"
    if [ ! -d "$TPM_DIR" ]; then
        echo "Cloning TPM..."
        git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
    else
        echo "TPM already installed."
    fi
fi

# 1. Get the absolute path of the directory where THIS script lives
DOTFILES_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
echo "Mapping dotfiles from: $DOTFILES_DIR"

# 2. Change to that directory so Stow knows where the 'packages' are
cd "$DOTFILES_DIR"

# Ensure target directories exist so Stow links contents rather than folding directories
mkdir -p "$HOME/.config"

# 3. List of folders to ignore (like .git, or the script itself)
IGNORE_LIST=("stow_dotfiles.sh" ".git" "README.md" "LICENSE" "helpfiles")

# 4. Loop through every directory in the dotfiles folder
for dir in */; do
    # Remove the trailing slash for the package name
    package=${dir%/}

    # Check if the package is in our ignore list
    if [[ ! " ${IGNORE_LIST[@]} " =~ " ${package} " ]]; then
        echo "${ACTION_WORD}: $package"

        # -v: Verbose (tells you what it's doing)
        # -R: Restow / -D: Delete (unstow)
        # -t: Target (explicitly set to $HOME)
        # --no-folding: Disable directory folding to prevent unfolding bugs with --dotfiles
        stow --no-folding --dotfiles -v "$ACTION" -t "$HOME" "$package"
    fi
done

if [ "$ACTION" = "-D" ]; then
    echo "Done! Your dotfiles have been unstowed."
else
    echo "Done! Your environment is now synchronized."
fi
