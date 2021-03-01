#!/bin/bash
rsync gh-dev::gentoo-etc-portage -aP /etc/portage/
ECrsync=$?
emerge --sync -q
ECesync=$?
emerge -1uDUN --rebuilt-binaries  --with-bdeps=y --changed-deps=y --tree @system --exclude gentoo-source --backtrack=100 -j2 -gK  --keep-going=y -n
emerge -1u --rebuilt-binaries  --with-bdeps=y --changed-deps=y --tree @world --exclude gentoo-source --backtrack=100 -j2 -gK --keep-going=y -n
emerge -1uDUN --rebuilt-binaries --with-bdeps=y --changed-deps=y --tree @world --exclude gentoo-source --backtrack=100 -j2 -gK  --keep-going=y -n
MAKEOPTS="-j1" emerge -1uDUN --with-bdeps=y --changed-deps=y --tree @world --exclude gentoo-source --backtrack=100 -j1 -bgk --keep-going=y -n
ECem=$?
MAKEOPTS="-j1" emerge -1bkg @preserved-rebuild -j1
ECrb=$?
emerge --depclean
ECdepclean=$?
eselect python update
eselect python cleanup
rc-status

echo ECrsync $ECrsync
echo ECesync $ECesync
echo ECem $ECem
echo ECrb $ECrb
echo ECdepclean $ECdepclean
if ! [[ $ECrsync || $ECesync || $ECem || $ECrb || $ECdepclean ]] ;then
	echo all update action returned 0
	exit 0
else
	echo error during update
	exit 1
	fi



