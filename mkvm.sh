#!/bin/sh
set -e
HOST="gh-vm"
DOMAIN="$(cat mydomain)"
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
http_proxy="http-proxy.lan:3142"
PORTAGE_BINHOST="http://gentoo-binhost.lan/packages"
NTP="ntp.lan"
MIRROR="http://mirror.eu.oneandone.net/linux/distributions/gentoo/gentoo"
CURRENT_STAGE=$(http_proxy="" wget $MIRROR/releases/amd64/autobuilds/latest-stage3-amd64-hardened%2bnomultilib.txt -O - --quiet |awk 'FNR == 3 {print $1}')
PORTAGE_SNAPSHOT="snapshots/portage-latest.tar.xz"
VM_IMG_SIZE_GB="4"
MAILTO=$(cat mailto)
mountDir="mountDir/root"
DEFPKGS="@tools app-admin/logrotate app-admin/sysstat app-arch/zstd app-emulation/qemu-guest-agent app-misc/screenfetch app-misc/tmux net-firewall/nftables sys-apps/pv sys-fs/btrfs-progs sys-fs/fuse sys-fs/ncdu sys-process/htop virtual/cron virtual/logger virtual/mta mail-mta/nullmailer app-editors/vim net-fs/nfs-utils sys-apps/pciutils app-portage/gentoolkit virtual/mailx net-mail/mailutils
"
#if test -z $IMGSIZEG ;then
#	VM_IMG_SIZE_GB=$IMGSIZEG
#	fi


enableDaemon_def(){
	msg "enabling $1 service"
	ln -s /etc/init.d/$1 $mountDir/etc/runlevels/default/$1
	}

disableDaemon_def(){
	msg "disabling $1 service"
	unlink $mountDir/etc/runlevels/default/$1
	}

msg(){
	printf "$GREEN$1$NC \n"
	}
warn(){
	printf "$YELLOW$1$NC \n"
	}
err(){
	printf "$RED$1$NC \n"
	}

copyUserGroup(){
	grep $1 /etc/passwd >> $mountDir/etc/passwd
	grep $1 /etc/shadow >> $mountDir/etc/shadow
	grep $1 /etc/group >> $mountDir/etc/group
	}

syssetup(){
	
	if ! test -f stage3-* ;then
		msg "downloading stage $CURRENT_STAGE"
		#wget -e use_proxy=yes -e http_proxy=${http_proxy} $MIRROR/releases/amd64/autobuilds/$CURRENT_STAGE
		wget $MIRROR/releases/amd64/autobuilds/$CURRENT_STAGE
	fi
	
	if ! test -f portage-latest.tar.xz ;then
		msg "downloading portage-latest.tar.xz"
		wget $MIRROR/$PORTAGE_SNAPSHOT
	fi
	
	msg "unpacking stage-3"
	if command -v pv >/dev/null ;then
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
	
	echo
	msg "modifying inittab"
	sed 's/^c[1-6]/#&/' -i $mountDir/etc/inittab
	sed '/^#s0/s/#//' -i $mountDir/etc/inittab

	ln -s /bin/busybox $mountDir/usr/bin/vi
	
	#warn "removing password from root"
	#sed -i '/root/s/*//' $mountDir/etc/shadow
	sed -i '/root/s/*//' $mountDir/etc/shadow
	if test -f id_rsa.pub ; then
		msg "copying ssh key"
		mkdir $mountDir/root/.ssh
		cp id_rsa.pub $mountDir/root/.ssh/authorized_keys
		fi
	
	msg "setting up eth0"
	ln -s /etc/init.d/net.lo $mountDir/etc/init.d/net.eth0
	enableDaemon_def 'net.eth0'
	echo 'hostname="gh-vm"' > $mountDir/etc/conf.d/hostname
	cat << 'EOF' > $mountDir/etc/conf.d/net
	config_eth0=dhcp
udhcpc_eth0="-T60"
EOF
	
	if test -f linux-*kvm.tar ; then 
		msg "installing kernel modules"
		tar xf linux-*kvm.tar -C $mountDir/
		fi

	msg "clock and ntpd"
	unlink $mountDir/etc/runlevels/boot/hwclock
	msg "copying host timezone config file"
	cp /etc/timezone $mountDir/etc/timezone
	cp /etc/localtime $mountDir/etc/localtime
	#cp /etc/ntp.conf $mountDir/etc/ntp.conf
	echo 'NTPD_OPTS="-N -p ntp.lan"' > $mountDir/etc/conf.d/busybox-ntpd
	
	msg fstab
	echo 'LABEL=vm-root	/	btrfs	compress=zstd,subvol=root 0 0' > $mountDir/etc/fstab 

	msg 'sshd prohibit-password'
	sed -i '/prohibit-password/s/\#//' $mountDir/etc/ssh/sshd_config
	msg 'adding bash aliasses'
	cat << 'EOF' >> $mountDir/etc/bash/bashrc
alias ll='ls -l'
alias mv='mv -i'
alias cp='cp -i'
alias rm='rm -i'
alias netstat-listen='netstat -tulnp|grep -v -e "127.0.0.1" -e "::1"'
alias ip='ip -color '
EOF

	msg "setting up portage"
	rsync gh-dev::gentoo-etc-portage -a $mountDir/etc/portage/
	msg "installing base software"
	#USE="sysv-utils" http_proxy="" PORTAGE_BINHOST="http://gentoo-binhost.lan/packages" ROOT=$mountDir PORTAGE_CONFIGROOT=$mountDir emerge -bgk --keep-going=y --with-bdeps=y -j2 $DEFPKGS @system --tree -uDNU
	http_proxy="" PORTAGE_BINHOST="http://gentoo-binhost.lan/packages" ROOT=$mountDir PORTAGE_CONFIGROOT=$mountDir emerge -bgk --with-bdeps=y --keep-going=y --with-bdeps=y -j2 $DEFPKGS @system --tree -uDNU || (echo 'portage returned error code, sleeping for 30 seconds. You can manually kill it if it is serious' && sleep 30)

	#msg "seting up ttys"
	#for x in tty2 tty3 tty4 tty5 tty6 ; do
	#	disableDaemon_def "agetty.$x"
	#	unlink $mountDir/etc/init.d/agetty.$x
	#	done

	##msg "setting up agetty.tty1"
	##ln -s /etc/init.d/agetty $mountDir/etc/init.d/agetty.tty1
	##enableDaemon_def 'agetty.tty1'
	#msg "setting up agetty.ttyS0"
	#ln -s /etc/init.d/agetty $mountDir/etc/init.d/agetty.ttyS0
	#enableDaemon_def 'agetty.ttyS0'
	#echo "	setting baud rate to 115200"
	#echo 'baud="115200"' > $mountDir/etc/conf.d/agent.ttyS0
	
	
	msg "setting logrotate option mailfirst to $MAILTO"
	sed -i "s/^nomail.*$/mail\ ${MAILTO}\nmailfirst/" $mountDir/etc/logrotate.conf
	msg "configuring nullmailer"
	echo "$DOMAIN" >  $mountDir/etc/nullmailer/defaultdomain
	echo "$HOST.$DOMAIN" > $mountDir/etc/nullmailer/me
	cat nullmailer_remotes > $mountDir/etc/nullmailer/remotes

	if test -z "$(grep nullmailer $mountDir/etc/passwd)" ;then
		warn "manually adding nullmailer user to /etc/passwd and shadow"
		warn "emerge has some problem adding it automatically"
		copyUserGroup "nullmail"
#		cat << 'EOF' >> $mountDir/etc/passwd
#nullmail:x:88:88:added by portage for nullmailer:/var/spool/nullmailer:/sbin/nologin
#EOF
#		cat << 'EOF' >> $mountDir/etc/shadow
#nullmail:!:17842::::::
#EOF
#		cat << 'EOF' >> $mountDir/etc/group
#nullmail:x:88:
#EOF
		fi
	
	msg "enabling daemons"
	enableDaemon_def busybox-ntpd
	enableDaemon_def nullmailer
	enableDaemon_def cronie
	enableDaemon_def sshd
	enableDaemon_def qemu-guest-agent
	enableDaemon_def metalog
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

if ! test -z $TEMPL ;then
	msg 'special specific setup placeholder'
	source ./$TEMPL/conf.sh
	#case $TEMPL in
	#	"rt1")
	#		echo "trying to source $TEMPL conf file"
	#		source ./$TEMPL/conf.sh
	#		;;
	#	*)
	#		echo "TEMPL is wrong"
	#		;;
	#esac
	fi


if true ; then
	
	if test -d mountDir ;then
		umount mountDir || echo not mounted
		rm -rf mountDir
		fi
	if ! test -z NOCLEAN ;then
		if test -f vm.img ;then
			rm vm.img
			fi
		
		#fallocate file or create zero file with dd if filesystem
		#	doesn't support fallocate (example nfs)
		fallocate -l ${VM_IMG_SIZE_GB}G vm.img ||\
			dd if=/dev/zero of=vm.img bs=1G count=${VM_IMG_SIZE_GB} status=progress
		fi
	sync
	mkfs.btrfs -f -msingle vm.img
	mkdir -p mountDir
	mount vm.img -o compress=zstd,subvolid=0 mountDir
	btrfs sub create mountDir/snap/
	btrfs sub create mountDir/root/
	
	syssetup
	if ! [ -z "$NOSETUP" ] ; then
		syssetup
		fi
	if ! test -z "$TEMPL" ; then
		SPEC_SETUP
		fi
	btrfs sub snap -r mountDir/root/ mountDir/snap/root-ssetup
else
	btrfs sub del mountDir/root/
	btrfs sub snap mountDir/snap/root-ssetup mountDir/root/
	fi

btrfs sub snap -r mountDir/root mountDir/snap/root-final/
btrfs sub set-default mountDir/root
btrfs filesystem label mountDir/ vm-root 

umount mountDir
