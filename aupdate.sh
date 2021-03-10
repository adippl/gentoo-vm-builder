#!/bin/bash
#
#    gentoo VM image builder - shell scripts building Gentoo based VMs
#    Copyright (C) 2021  Adam Prycki
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License along
#    with this program; if not, write to the Free Software Foundation, Inc.,
#    51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#

rsync gh-dev::gentoo-etc-portage -aP /etc/portage/
ECrsync=$?
emerge --sync -q
ECesync=$?
emerge -1uDUN --rebuilt-binaries  --with-bdeps=y --tree @system --exclude gentoo-source --backtrack=100 -j2 -gK  --keep-going=y -n
emerge -1u --rebuilt-binaries  --with-bdeps=y --tree @world --exclude gentoo-source --backtrack=100 -j2 -gK --keep-going=y -n
emerge -1uDUN --rebuilt-binaries --with-bdeps=y --tree @world --exclude gentoo-source --backtrack=100 -j2 -gK  --keep-going=y -n
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



