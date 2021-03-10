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

function writeDefault_nft(){
	cat <<'EOF' > $mountDir/var/lib/nftables/rules-save
#!/sbin/nft -f
flush ruleset
table inet filter {
	chain input {
		type filter hook input priority filter; policy drop;
		ct state invalid counter drop comment "early drop of invalid packets"
		ct state { established, related } counter accept comment "accept all connections related to connections made by us"
		iif "lo" accept comment "accept loopback"
		iif != "lo" ip daddr 127.0.0.0/8 counter drop comment "drop connections to loopback not coming from loopback"
		iif != "lo" ip6 daddr ::1 counter drop comment "drop connections to loopback not coming from loopback"
		ip protocol icmp counter accept comment "accept all ICMP types"
		ip6 nexthdr ipv6-icmp counter accept comment "accept all ICMP types"
		tcp dport 22 counter accept comment "accept SSH"
		counter comment "count dropped packets"
	}

	chain forward {
		type filter hook forward priority filter; policy drop;
		counter comment "count dropped packets"
	}

	chain output {
		type filter hook output priority filter; policy accept;
		counter comment "count accepted packets"
	}
}
EOF
	}

enableDaemon_def(){
	msg "enabling $1 service"
	ln -s /etc/init.d/$1 $mountDir/etc/runlevels/default/$1
	}

disableDaemon_def(){
	msg "disabling $1 service"
	unlink $mountDir/etc/runlevels/default/$1
	}

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
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
	copyGroup $1
	copyUser $1
	}

copyGroup(){
	grep $1 /etc/group >> $mountDir/etc/group
	}

copyUser(){
	grep $1 /etc/passwd >> $mountDir/etc/passwd
	grep $1 /etc/shadow >> $mountDir/etc/shadow
	}

function templBaseConfig(){
	msg "setting hostname"
	echo "hostname=\"$HOST\"" > $mountDir/etc/conf.d/hostname
	
	msg "configuring nullmailer"
	echo "$DOMAIN" >  $mountDir/etc/nullmailer/defaultdomain
	echo "$HOST.$DOMAIN" > $mountDir/etc/nullmailer/me
	
	if [ "$USE_CACHED" != "" ] && [ -f $USE_CACHED ] ;then
		msg "installing template specific packages"
		http_proxy="" PORTAGE_BINHOST="http://gentoo-binhost.lan/packages" ROOT=$mountDir PORTAGE_CONFIGROOT=$mountDir emerge -ubgk --rebuilt-binaries=y --with-bdeps=y --keep-going=y -j2 $TEMPLPKGS || (echo 'portage returned error code, sleeping for 30 seconds. You can manually kill it if it is serious' && sleep 30)
		fi
	}

baseSystemSetup(){
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
	
	if test -f linux-*kvm.tar.xz ; then 
		msg "installing kernel modules"
		tar xJf linux-*kvm.tar.xz -C $mountDir/ --exclude 'System.map*' --exclude 'config*' --exclude 'kern*'
		fi
	
	echo
	msg "modifying inittab"
	sed 's/^c[1-6]/#&/' -i $mountDir/etc/inittab
	sed '/^#s0/s/#//' -i $mountDir/etc/inittab

	ln -s /bin/busybox $mountDir/usr/bin/vi
	
	#warn "removing password from root"
	#sed -i '/root/s/*//' $mountDir/etc/shadow
	if test -f id_rsa.pub ; then
		msg "copying ssh key"
		mkdir $mountDir/root/.ssh
		cp id_rsa.pub $mountDir/root/.ssh/authorized_keys
		fi
	
	msg "setting up eth0"
	ln -s /etc/init.d/net.lo $mountDir/etc/init.d/net.eth0
	enableDaemon_def 'net.eth0'
#	cat << 'EOF' > $mountDir/etc/conf.d/net
#	config_eth0=dhcp
#udhcpc_eth0="-T60"
#EOF
	msg "setting hostname"
	echo "hostname=\"$HOST\"" > $mountDir/etc/conf.d/hostname
	
	msg "clock and ntpd"
	unlink $mountDir/etc/runlevels/boot/hwclock
	msg "copying host timezone config file"
	cp /etc/timezone $mountDir/etc/timezone
	cp /etc/localtime $mountDir/etc/localtime
	#cp /etc/ntp.conf $mountDir/etc/ntp.conf
	echo 'NTPD_OPTS="-N -p ntp.lan"' > $mountDir/etc/conf.d/busybox-ntpd
	
	msg fstab
	echo 'LABEL=vm-root	/	btrfs	compress=zstd,subvol=root 0 0' > $mountDir/etc/fstab 
	echo 'LABEL=vm-root	/mnt/a	btrfs	compress=zstd,subvolid=0 0 0' >> $mountDir/etc/fstab 
	mkdir $mountDir/mnt/a

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
	http_proxy="" PORTAGE_BINHOST="http://gentoo-binhost.lan/packages" ROOT=$mountDir PORTAGE_CONFIGROOT=$mountDir emerge -ubgk --rebuilt-binaries=y --with-bdeps=y --keep-going=y -j2 $DEFPKGS || (echo 'portage returned error code, sleeping for 30 seconds. You can manually kill it if it is serious' && sleep 30)

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
		fi
	
	msg "enabling daemons"
	enableDaemon_def busybox-ntpd
	enableDaemon_def nullmailer
	enableDaemon_def cronie
	enableDaemon_def sshd
	enableDaemon_def qemu-guest-agent
	enableDaemon_def metalog
	enableDaemon_def nftables
	
	msg "installing update scripts"
	cp update.sh $mountDir/root/
	chmod +x $mountDir/root/update.sh
	cp aupdate.sh $mountDir/root/
	chmod +x $mountDir/root/aupdate.sh
	ln -s /root/aupdate.sh $mountDir/etc/cron.weekly/aupdate.sh
	cp kupdate.sh $mountDir/root/
	chmod +x $mountDir/root/kupdate.sh
	ln -s /root/kupdate.sh $mountDir/etc/cron.weekly/kupdate.sh
	cat <<'EOF' > $mountDir/etc/update.conf
export TYPE="kvm"
export IMODE="VM"
EOF
	}
