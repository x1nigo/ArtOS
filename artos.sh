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

progsfile="https://raw.githubusercontent.com/x1nigo/artos/main/progs.csv"
dotfilesrepo="https://github.com/x1nigo/dotfiles.git"
aurhelper="yay"

error() {
	# Log to stderr and exit with failure.
	printf "%s\n" "$1" >&2
	exit 1
}

getwhiptail() {
	echo "
Updating repositories and installing dependencies...
"
	pacman -S --noconfirm --needed libnewt make curl rsync || error "Failed to update repositories and install dependencies."
}

openingmsg() {
	whiptail --title "Introduction" \
		--msgbox "Welcome to Chris Iñigo's Bootstrapping Script for Artix Linux! This will install a fully-functioning linux desktop, which I hope may prove useful to you as it did for me.\\n\\n-Chris" 12 70 || error "Failed to show opening message."
}

getuserandpass() {
	# Prompts user for new username an password.
	name=$(whiptail --inputbox "First, please enter a name for the user account." 10 70 3>&1 1>&2 2>&3 3>&1) || exit 1
	while ! echo "$name" | grep -q "^[a-z_][a-z0-9_-]*$"; do
		name=$(whiptail --nocancel --inputbox "Username not valid. Give a name beginning with a letter, with only lowercase letters, - or _." 10 70 3>&1 1>&2 2>&3 3>&1)
	done
	pass1=$(whiptail --nocancel --passwordbox "Enter a password for that user." 10 60 3>&1 1>&2 2>&3 3>&1)
	pass2=$(whiptail --nocancel --passwordbox "Retype password." 10 70 3>&1 1>&2 2>&3 3>&1)
	while ! [ "$pass1" = "$pass2" ]; do
		unset pass2
		pass1=$(whiptail --nocancel --passwordbox "Passwords do not match.\\n\\nEnter password again." 10 60 3>&1 1>&2 2>&3 3>&1)
		pass2=$(whiptail --nocancel --passwordbox "Retype password." 10 70 3>&1 1>&2 2>&3 3>&1)
	done
}

preinstallmsg() {
	whiptail --title "Resolution" \
		--yes-button "Let's go!" \
		--no-button "I...I can barely stand." \
		--yesno "The installation script will be fully automated from this point onwards.\\n\\nAre you ready to begin?" 12 70 || {
		clear
		exit 1
	}
}

adduserandpass() {
	# Adds user `$name` with password $pass1.
	whiptail --infobox "Adding user \"$name\"..." 7 50
	useradd -m -g wheel -s /bin/bash "$name" >/dev/null 2>&1 ||
	export repodir="/home/$name/.local/src"
	mkdir -p "$repodir"
	chown -R "$name":wheel "$(dirname "$repodir")"
	echo -e "$pass1\n$pass1" | passwd "$name" >/dev/null 2>&1
	unset pass1 pass2
}

permission() {
	echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/00-wheels-can-sudo
}

getaurhelper() {
	whiptail --infobox "Installing AUR helper..." 7 50
	sudo -u "$name" git -C "$repodir" clone https://aur.archlinux.org/$aurhelper.git >/dev/null 2>&1
	cd "$repodir"/$aurhelper
	sudo -u "$name" makepkg -si >/dev/null 2>&1
}

refreshkeys() {
	case "$(readlink -f /sbin/init)" in
	*systemd*)
		whiptail --infobox "Refreshing Arch Keyring..." 7 40
		pacman --noconfirm -S archlinux-keyring >/dev/null 2>&1
		;;
	*)
		whiptail --infobox "Enabling Arch Repositories for more a more extensive software collection..." 7 40
		pacman --noconfirm --needed -S \
			artix-keyring artix-archlinux-support >/dev/null 2>&1
		grep -q "^\[extra\]" /etc/pacman.conf ||
			echo "[extra]
Include = /etc/pacman.d/mirrorlist-arch" >>/etc/pacman.conf
		pacman -Sy --noconfirm >/dev/null 2>&1
		pacman-key --populate archlinux >/dev/null 2>&1
		;;
	esac
}

finalize() {
	whiptail --title "Done!" --msgbox "Installation complete! If you see this message, then there's a pretty good chance that there were no (hidden) errors. You may log out and log back in with your new name.\\n\\n-Chris" 12 60
}

### Main Installation ###

installpkgs() {
	[ ! -f ~/artos/progs.csv ] && { curl -Ls "$progsfile" | sed '/^#/d' > /tmp/progs.csv } || { cat ~/artos/progs.csv | sed '/^#/d' > /tmp/progs.csv }
	total=$(( $(wc -l < /tmp/progs.csv) ))
	n=0
	while IFS=, read -r tag program description
	do
		n=$(( n + 1 ))
		whiptail --infobox "Installing \`$program\` ($n of $total). \"$description.\"" 8 70
		case $tag in
			G) sudo -u "$name" git -C "$repodir" clone "$program" >/dev/null 2>&1 ;;
			A) sudo -u "$name" yay -S --noconfirm --needed "$program" >/dev/null 2>&1 ;;
			*) pacman -S --noconfirm --needed "$program" >/dev/null 2>&1 ;;
		esac
	done < /tmp/progs.csv
}

getdotfiles() {
	whiptail --infobox "Downloading and installing config files..." 7 60
	sudo -u "$name" git -C "$repodir" clone "$dotfilesrepo" >/dev/null 2>&1
	cd "$repodir"/dotfiles
	shopt -s dotglob && sudo -u "$name" rsync -r * /home/$name/
	# Install the file manager.
	cd /home/$name/.config/lf && chmod +x lfrun scope cleaner && mv lfrun /usr/bin/
	# Link specific filed to home directory.
	ln -sf /home/$name/.config/x11/xprofile /home/$name/.xprofile
	ln -sf /home/$name/.config/shell/profile /home/$name/.zprofile
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

compiless() {
	whiptail --infobox "Compiling suckless software..." 7 40
	for dir in $(echo "dwm st dmenu dwmblocks"); do
		cd "$repodir"/"$dir" && make clean install >/dev/null 2>&1
	done
}

removebeep() {
	rmmod pcspkr 2>/dev/null
	echo "blacklist pcspkr" >/etc/modprobe.d/nobeep.conf || error "Failed to remove the beep sound. That's annoying."
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

changeshell() {
	# Make sure the user's shell is `zsh` and root's is `bash`.
	chsh -s /bin/bash >/dev/null 2>&1
	chsh -s /bin/zsh $name >/dev/null 2>&1
	echo "# .bashrc

alias ls='ls --color=auto'
PS1=\"\[\e[1;31m\]\u on \h \[\e[1;34m\]\w\[\e[0m\]
-\[\e[1;31m\]&\[\e[0m\] \""> ~/.bashrc || error "Could not change shell for the user."
}

depower() {
	echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/00-wheels-can-sudo
	rm /etc/sudoers.d/wheel >/dev/null 2>&1 # Remove the spare wheel config file
	echo "%wheel ALL=(ALL:ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/poweroff,/usr/bin/reboot,/usr/bin/su,/usr/bin/make clean install,/usr/bin/make install,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/pacman -Sy,/usr/bin/pacman -Su,/usr/bin/mount,/usr/bin/umount,/usr/bin/cryptsetup,/usr/bin/simple-mtpfs,/usr/bin/fusermount" > /etc/sudoers.d/01-no-password-commands
}

### The Main Function ###

# Installs whiptail program to run alongside this script.
getwhiptail

# The opening message.
openingmsg

# Gets the username and password.
getuserandpass || error "Failed to get username and password."

# The pre-install message. Last chance to get out of this.
preinstallmsg|| error "Failed to prompt the user properly."

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
compiless || error "Failed to compile all suckless software."

# Remove the beeping sound of your computer.
removebeep

# Cleans the files and directories.
cleanup

# Change shell of the user to `zsh`.
changeshell

# De-power the user from infinite greatness.
depower || error "Could not bring back user from his God-like throne of sudo privilege."

# The closing message.
finalize
