#!/bin/bash
#     _         _
#    / \   _ __| |_ ___  ___
#   / _ \ | '__| __/ _ \/ __|
#  / ___ \| |  | || (_) \__ \
# /_/   \_\_|   \__\___/|___/

# Chris Iñigo's Bootstrapping Script for Artix Linux
# by Chris Iñigo <chris@x1nigo.xyz>

# Things to note:
# - Run this script as ROOT!

dotfilesrepo="https://github.com/x1nigo/dotfiles.git"
aurhelper="yay"

error() {
	# Log to stderr and exit with failure.
	printf "%s\n" "$1" >&2
	exit 1
}

getupdate() {
	echo "
Updating repositories and installing dependencies...
"
	pacman -S --noconfirm --needed make rsync || error "Failed to update repositories and install dependencies."
}

openingmsg() { cat << EOF

Welcome!

This script will install a fully-functioning unix system, which I hope may prove useful to you as it did for me.

EOF

printf "%s" "Press \`Return\` to continue."
read -r enter
}

getuserandpass() {
	# Prompts user for new username an password.
	printf "%s" "Username: "
	read -r name
	printf "%s" "Password: "
	read -r  password
}

adduserandpass() {
	# Adds user `$name` with password.
	useradd -m -g wheel "$name"
	export repodir="/home/$name/.local/src"
	mkdir -p "$repodir"
	chown -R "$name":wheel "$(dirname "$repodir")"
	echo -e "$password\n$password" | passwd "$name"
	unset password
}

permission() {
	echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/00-wheels-can-sudo
}

getaurhelper() {
	sudo -u "$name" git -C "$repodir" clone https://aur.archlinux.org/$aurhelper.git
	cd "$repodir"/$aurhelper
	sudo -u "$name" makepkg --noconfirm -si
}

refreshkeys() {
	case "$(readlink -f /sbin/init)" in
	*systemd*)
		pacman --noconfirm -S archlinux-keyring
		;;
	*)
		pacman --noconfirm --needed -S \
			artix-keyring artix-archlinux-support
		grep -q "^\[extra\]" /etc/pacman.conf ||
			echo "[extra]
Include = /etc/pacman.d/mirrorlist-arch" >>/etc/pacman.conf
		pacman -Sy --noconfirm
		pacman-key --populate archlinux
		;;
	esac
}

finalize() { cat << EOF

Done!

Congratulations, you now have an operating system! Please reboot a log in with your username and password.

EOF
}

### Main Installation ###

installpkgs() {
	cat ~/artos/progs.csv | sed '/^#/d' > /tmp/progs.csv
	while IFS=, read -r tag program description
	do
		case $tag in
			G) sudo -u "$name" git -C "$repodir" clone "$program" ;;
			A) sudo -u "$name" yay -S --noconfirm --needed "$program" ;;
			*) pacman -S --noconfirm --needed "$program" ;;
		esac
	done < /tmp/progs.csv
}

getdotfiles() {
	sudo -u "$name" git -C "$repodir" clone "$dotfilesrepo"
	cd "$repodir"/dotfiles
	shopt -s dotglob && sudo -u "$name" rsync -r * /home/$name/
	# Link the .shrc file
	ln -s /home/$name/.config/shell/shrc /home/$name/.shrc
	cp /home/$name/.shrc /home/$name/.bashrc
	# Create a vimrc file linked from the neovim config
	ln -s /home/$name/.config/nvim/init.vim /home/$name/.vimrc
}

updateudev() {
	mkdir -p /etc/X11/xorg.conf.d
	echo "Section \"InputClass\"
Identifier \"touchpad\"
Driver \"libinput\"
MatchIsTouchpad \"on\"
	Option \"Tapping\" \"on\"
	Option \"NaturalScrolling\" \"on\"
EndSection" > /etc/X11/xorg.conf.d/30-touchpad.conf || error "Failed to update the udev files."
}

suckless() {
	for dir in $(echo "dwm st dmenu"); do
		cd "$repodir"/"$dir" && make clean install
	done
}

cleanup() {
	cd # Return to root
 	rm -r ~/artos ; rm /tmp/progs.csv
	rm -r "$repodir"/dotfiles "$repodir"/$aurhelper
	rm -r /home/$name/.git
	rm -r /home/$name/README.md
 	sudo -u $name mkdir -p /home/$name/.config/gnupg/
	# Give gnupg folder the correct permissions.
  	find /home/$name/.config/gnupg -type f -exec chmod 600 {} \;
	find /home/$name/.config/gnupg -type d -exec chmod 700 {} \;
 	sudo -u $name mkdir -p /home/$name/.config/mpd/playlists/
 	sudo -u $name chmod -R +x /home/$name/.local/bin/* || error "Failed to remove unnecessary files and other cleaning."
}

depower() {
	echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/00-wheels-can-sudo
	rm /etc/sudoers.d/wheel >/dev/null 2>&1 # Remove the spare wheel config file
	echo "%wheel ALL=(ALL:ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/poweroff,/usr/bin/reboot,/usr/bin/su,/usr/bin/make clean install,/usr/bin/make install,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/pacman -Sy,/usr/bin/pacman -Su,/usr/bin/mount,/usr/bin/umount,/usr/bin/cryptsetup,/usr/bin/simple-mtpfs,/usr/bin/fusermount" > /etc/sudoers.d/01-no-password-commands
}

### The Main Function ###

# Installs whiptail program to run alongside this script.
getupdate

# The opening message.
openingmsg

# Gets the username and password.
getuserandpass || error "Failed to get username and password."

# Add the username and password given earlier.
adduserandpass || error "Failed to add user and password."

# Grants unlimited permission to the root user (temporarily).
permission || error "Failed to change permissions for user."

# Install the AUR helper.
getaurhelper || error "Failed to get an AUR helper."

# Refresh the Arch/Artix Linux keys.
refreshkeys || error "Failed to get updated keys."

# The main installation loop.
installpkgs || error "Failed to install the necessary packages."

# Install the dotfiles in the user's home directory.
getdotfiles || error "Failed to install the user's dotfiles."

# Make pacman colorful, concurrent downloads and Pacman eye-candy.
grep -q "ILoveCandy" /etc/pacman.conf || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
sed -Ei "s/^#(ParallelDownloads).*/\1 = 5/;/^#Color$/s/#//" /etc/pacman.conf

# Updates udev rules to allow tapping and natural scrolling, etc.
updateudev

# Compiling suckless software.
suckless || error "Failed to compile all suckless software."

# Cleans the files and directories.
cleanup

# De-power the user from infinite greatness.
depower || error "Could not bring back user from his God-like throne of sudo privilege."

# The closing message.
finalize
