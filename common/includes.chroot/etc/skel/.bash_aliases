# ChaoticEvil default shell aliases
# Seeded into every new user account via /etc/skel/.bash_aliases.
# Ubuntu's stock ~/.bashrc sources this file automatically if it exists,
# so we never have to carry a full custom .bashrc.
#
# Tip: run `aliases` to print this list at any time.

# Navigation
alias cd..='cd ..'
alias cd...='cd ../..'

# Listing
alias ll='ls -alFh'
alias la='ls -A'
alias l='ls -CF'
alias lt='ls -alFhtr'          # newest last

# System maintenance
alias update='sudo apt update && sudo apt upgrade'
alias fullupgrade='sudo apt update && sudo apt full-upgrade'
alias install='sudo apt install'
alias search='apt search'
alias autoremove='sudo apt autoremove --purge'

# System info
alias df='df -h'
alias free='free -h'
alias ports='ss -tulanp'

# Colour + safety
alias grep='grep --color=auto'
alias ip='ip -color=auto'

# Show these aliases
alias aliases='grep -E "^alias" ~/.bash_aliases'
