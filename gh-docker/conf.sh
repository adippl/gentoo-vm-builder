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

HOST="gh-docker"
dir=$HOST
TEMPL_VM_IMG_SIZE_GB="10"
CPU="6"
MEM="2048"
MAC="76:6d:00:00:00:12"
BRIDGE="brvl6"
TEMPLPKGS="app-emulation/docker"
DEFPKGS="${DEFPKGS} ${TEMPLPKGS}"

SPEC_SETUP(){
	templBaseConfig
	copyGroup docker
	enableDaemon_def docker
	mkdir -p $mountDir/var/lib/docker/
	btrfs subvolume create $mountDir/var/lib/docker/btrfs
	
	}

