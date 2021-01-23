#!/bin/sh
#set -e
RED='\033[1;31m'
GREEN='\033[1;32m'
NC='\033[0m' # No Color
http_proxy="http-proxy.lan:3142"
PORTAGE_BINHOST="http://gentoo-binhost.lan/packages"
NTP="ntp.lan"
MIRROR="http://mirror.eu.oneandone.net/linux/distributions/gentoo/gentoo"
CURRENT_STAGE=$(http_proxy="" wget $MIRROR/releases/amd64/autobuilds/latest-stage3-amd64-hardened%2bnomultilib.txt -O - --quiet |awk 'FNR == 3 {print $1}')
PORTAGE_SNAPSHOT="snapshots/portage-latest.tar.xz"
mountDir="mountDir/root/"


enableDaemon_def(){
	msg "enabling $1 daemon"
	ln -s /etc/init.d/$1 $mountDir/etc/runlevels/default/$1
	}

msg(){
	printf "$RED$1$NC \n"
	}

syssetup(){
	echo
	msg "modifying inittab"
	sed 's/^c[1-6]/#&/' -i $mountDir/etc/inittab
	sed '/^#s0/s/#//' -i $mountDir/etc/inittab
	
	ln -s /bin/busybox $mountDir/bin/vi
	
	msg "removing password from root"
	sed -i '/root/s/*//' $mountDir/etc/shadow
	if test -f id_rsa.pub ; then
		msg "copying ssh key"
		mkdir $mountDir/root/.ssh
		cp id_rsa.pub $mountDir/root/.ssh/authorized_keys
		fi
	
	msg "setting up eth0"
	ln -s /etc/init.d/net.lo $mountDir/etc/init.d/net.eth0
	#ln -s /etc/init.d/net.eth0 $mountDir/etc/runlevels/default/net.eth0
	enableDaemon_def 'net.eth0'
	echo 'hostname="gh-vm"' > $mountDir/etc/conf.d/hostname
	cat << 'EOF' > $mountDir/etc/conf.d/net.eth0
	config_eth0=dhcp
udhcpc_eth0="-T60"
EOF
	
	if test -f linux-*kvm.tar ; then 
		msg "installing kernel modules"
		tar xf linux-*kvm.tar -C $mountDir/
		fi

	msg "clock and ntpd"
	#ln -s /etc/init.d/busybox-ntpd $mountDir/etc/runlevels/default/busybox-ntpd
	enableDaemon_def busybox-ntpd
	unlink $mountDir/etc/runlevels/boot/hwclock
	msg "copying host timezone config file"
	cp /etc/timezone $mountDir/etc/timezone
	cp /etc/localtime $mountDir/etc/localtime
	cp /etc/ntp.conf $mountDir/etc/ntp.conf
	echo > $mountDir/etc/conf.d/busybox-ntpd
	
	msg fstab
	echo 'LABEL=vm-root	/	btrfs	compress=zstd,subvol=root 0 0' > $mountDir/etc/fstab 

	#msg sshd prohibit-password
	#sed -i '/prohibit-password/s/\#//' $mountDir/etc/ssh/sshd_config
	
	msg "setting up portage"
	rsync 10.0.6.205::gentoo-etc-portage -a $mountDir/etc/portage/
	msg "installing basic software"
	http_proxy="" PORTAGE_BINHOST="http://gentoo-binhost.lan/packages" ROOT=$mountDir PORTAGE_CONFIGROOT=$mountDir emerge -bgk --keep-going=y --with-bdeps=y -j2 app-emulation/qemu-guest-agent nftables nfs-utils @tools
	msg "enabling daemons"
	msg "enabling cronie"
	#ln -s /etc/init.d/cronie $mountDir/etc/runlevels/default/cronie
	enableDaemon_def cronie
	
	#ln -s /etc/init.d/sshd $mountDir/etc/runlevels/default/sshd
	enableDaemon_def sshd
	#sg "enabling busybox-ntp"
	#ln -s /etc/init.d/busybox-ntp $mountDir/etc/runlevels/default/busybox-ntp
	
	#msg "enabling qemu-guest-agent"
	#ln -s /etc/init.d/qemu-guest-agent $mountDir/etc/runlevels/default/qemu-guest-agent
	enableDaemon_def qemu-guest-agent
	
	#msg "enabling metalog"
	#ln -s /etc/init.d/metalog $mountDir/etc/runlevels/default/metalog
	enableDaemon_def metalog
	
	#msg "enabling nftables"
	#ln -s /etc/init.d/nftables $mountDir/etc/runlevels/default/nftables
	enableDaemon_def nftables
	cat <<'EOF' > $mountDir/var/lib/nftables/rules-save
#!/sbin/nft -f
flush ruleset
table inet filter {
	chain input {
		type filter hook input priority filter; policy drop;
		ct state invalid counter packets 0 bytes 0 drop comment "early drop of invalid packets"
		ct state { established, related } counter packets 0 bytes 0 accept comment "accept all connections related to connections made by us"
		iif "lo" accept comment "accept loopback"
		iif != "lo" ip daddr 127.0.0.0/8 counter packets 0 bytes 0 drop comment "drop connections to loopback not coming from loopback"
		iif != "lo" ip6 daddr ::1 counter packets 0 bytes 0 drop comment "drop connections to loopback not coming from loopback"
		ip protocol icmp counter packets 0 bytes 0 accept comment "accept all ICMP types"
		ip6 nexthdr ipv6-icmp counter packets 0 bytes 0 accept comment "accept all ICMP types"
		tcp dport 22 counter packets 0 bytes 0 accept comment "accept SSH"
		counter packets 0 bytes 0 comment "count dropped packets"
	}

	chain forward {
		type filter hook forward priority filter; policy drop;
		counter packets 0 bytes 0 comment "count dropped packets"
	}

	chain output {
		type filter hook output priority filter; policy accept;
		counter packets 0 bytes 0 comment "count accepted packets"
	}
}
EOF
	
	msg "installing update scripts"
	cp update.sh $mountDir/root/
	cp aupdate.sh $mountDir/root/
	chmod +x $mountDir/root/*.sh
	ln -s /root/aupdate.sh $mountDir/etc/cron.weekly/aupdate.sh
	}


if ! test -z SKIPSSETUP ; then
	
	if test -f vm.img ;then
		rm vm.img
		umount mountDir
		fi
	
	fallocate -l 2G vm.img
	mkfs.btrfs -f -msingle vm.img
	mkdir -p mountDir
	mount vm.img -o compress=zstd,subvolid=0 mountDir
	btrfs sub create mountDir/snap/
	btrfs sub create mountDir/root/
	
	
	msg "downloading files"
	
	if ! test -f stage3-* ;then
		msg "downloading stage $CURRENT_STAGE"
		#wget -e use_proxy=yes -e http_proxy=${http_proxy} $MIRROR/releases/amd64/autobuilds/$CURRENT_STAGE
		wget $MIRROR/releases/amd64/autobuilds/$CURRENT_STAGE
	fi
	
	if ! test -f portage-latest.tar.xz ;then
		msg "downloading portage-latest.tar.xz"
		wget $MIRROR/$PORTAGE_SNAPSHOT
	fi
	
	msg "unpacking stage"
	if command -v pv >/dev/null ;then
	#	cat stage3-* |pv -s $(du -b stage3-* |cut -f 1) | tar xpJ --xattrs-include='*.*' --numeric-owner -C mountDir
		pv stage3-* | tar xpJ --xattrs-include='*.*' --numeric-owner -C $mountDir
	else
		tar xpJf stage3-* --xattrs-include='*.*' --numeric-owner -C $mountDir
	fi
	
	msg "unpacking portage"
	if command -v pv >/dev/null ;then
		pv portage-latest.tar.xz | tar xpJ --xattrs-include='*.*' --numeric-owner -C $mountDir/usr
	else
		tar xpJf portage-latest.tar.xz --xattrs-include='*.*' --numeric-owner -C $mountDir/usr
		fi
	
	syssetup
	btrfs sub snap -r mountDir/root/ mountDir/snap/root-ssetup
else
	btrfs sub del mountDir/root/
	btrfs sub snap mountDir/snap/root-ssetup mountDir/root/
	fi


if ! test -z SPECIFICSETUP ; then
	msg 'special specific setup placeholder'
	fi


btrfs sub snap -r mountDir/root mountDir/snap/root-final/
btrfs sub set-default mountDir/root
btrfs filesystem label mountDir/ vm-root 

umount mountDir
