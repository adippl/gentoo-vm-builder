#!/bin/sh
set -e
source ./functions.sh
HOST="gh-vm"
DOMAIN="$(cat mydomain)"
NC='\033[0m' # No Color
http_proxy="http-proxy.lan:3142"
PORTAGE_BINHOST="http://gentoo-binhost.lan/packages"
NTP="ntp.lan"
MIRROR="http://mirror.eu.oneandone.net/linux/distributions/gentoo/gentoo"
CURRENT_STAGE=$(http_proxy="" wget $MIRROR/releases/amd64/autobuilds/latest-stage3-amd64-hardened%2bnomultilib.txt -O - --quiet |awk 'FNR == 3 {print $1}')
PORTAGE_SNAPSHOT="snapshots/portage-latest.tar.xz"
VM_IMG_SIZE_GB="3"
MAILTO=$(cat mailto)
mountDir="mountDir/root"
DEFPKGS="@tools app-admin/logrotate app-admin/sysstat app-arch/zstd app-emulation/qemu-guest-agent app-misc/screenfetch app-misc/tmux net-firewall/nftables sys-apps/pv sys-fs/btrfs-progs sys-fs/fuse sys-fs/ncdu sys-process/htop virtual/cron virtual/logger virtual/mta mail-mta/nullmailer app-editors/vim net-fs/nfs-utils sys-apps/pciutils app-portage/gentoolkit virtual/mailx net-mail/mailutils
"
#if test -z $IMGSIZEG ;then
#	VM_IMG_SIZE_GB=$IMGSIZEG
#	fi


	
if test -d mountDir ;then
	umount mountDir || echo not mounted
	rm -rf mountDir
	fi
	

if ! test -z $TEMPL ;then
	msg 'special specific setup placeholder'
	source ./$TEMPL/conf.sh
	fi

if [ "$USE_CACHED" != "" ] && [ -f $USE_CACHED ] ;then
	NOSETUP=1
	msg "copying $USE_CACHED"
	extendBy=$(( $TEMPL_VM_IMG_SIZE_GB - $VM_IMG_SIZE_GB ))
	if (( $extendBy > 0 )) ; then
		EXTENDED=1
		fallocate -l ${extendBy}G extension ||\
			dd if=/dev/zero of=extension bs=1G count=${extendBy} status=progress
		cat $USE_CACHED $extension > vm.img
	else
		cp $USE_CACHED vm.img
		fi
	fi

if test "$NOSETUP" != "1" ;then
	if test -f vm.img ;then
		rm vm.img
		fi
	#fallocate file or create zero file with dd if filesystem
	#	doesn't support fallocate (example nfs)
	touch vm.img
	#chattr +C vm.img
	fallocate -l ${VM_IMG_SIZE_GB}G vm.img ||\
		dd if=/dev/zero of=vm.img bs=1G count=${VM_IMG_SIZE_GB} status=progress
	sync
	mkfs.btrfs -f -msingle vm.img
	fi
mkdir -p mountDir
mount vm.img -o compress=zstd,subvolid=0 mountDir
if test "$NOSETUP" != "1" ;then
	btrfs sub create mountDir/snap/
	btrfs sub create mountDir/root/
	fi

if test "$NOSETUP" != "1" ; then
	baseSystemSetup
	fi
if ! test -z "$TEMPL" ; then
	SPEC_SETUP
	fi

if test "$NOSETUP" != "1" ; then
	btrfs sub snap -r mountDir/root/ mountDir/snap/root-ssetup
else
	btrfs sub del mountDir/snap/root-final
	fi

btrfs sub snap -r mountDir/root mountDir/snap/root-final
btrfs sub set-default mountDir/root
btrfs filesystem label mountDir/ vm-root 
if test "$EXTENDED" = "1" ; then
	msg "Extending filesystem to ${TEMPL_VM_IMG_SIZE_GB}GB"
	btrfs filesystem resize max mountDir
	fi

umount mountDir
sync

if ! test -z "$TEMPL" ; then
	cp vm.img $TEMPL.img
	fi
if test "$DEPLOY" = "1" ;then
	HOST=$HOST CPU=$CPU MEM=$MEM NET_MAC=$MAC NET_BRIDGE=$BRIDGE ./deploy.sh
	fi
