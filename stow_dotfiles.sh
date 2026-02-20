#!/usr/bin/env bash

# tmot's configs
# GNU Stow should be installed. Run this from the directory that the script
# lives in.

# 1. Get the absolute path of the directory where THIS script lives
DOTFILES_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

echo "Mapping dotfiles from: $DOTFILES_DIR"

# 2. Change to that directory so Stow knows where the 'packages' are
cd "$DOTFILES_DIR"

# 3. List of folders to ignore (like .git, or the script itself)
IGNORE_LIST=("stow_dotfiles.sh" ".git" "README.md" "LICENSE")

# 4. Loop through every directory in the dotfiles folder
for dir in */; do
    # Remove the trailing slash for the package name
    package=${dir%/}

    # Check if the package is in our ignore list
    if [[ ! " ${IGNORE_LIST[@]} " =~ " ${package} " ]]; then
        echo "Stowing: $package"

        # -v: Verbose (tells you what it's doing)
        # -R: Restow (refreshes links if they already exist)
        # -t: Target (explicitly set to $HOME)
        stow --dotfiles -v -R -t "$HOME" "$package"
    fi
done

echo "Done! Your environment is now synchronized."
