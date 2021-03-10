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

HOST="gh-portage"
dir=$HOST
VM_IMG_SIZE_GB="30"
CPU="2"
MEM="512"
MAC="76:6d:00:00:00:03"
BRIDGE="brvl6"
TEMPLPKGS="app-vim/vim-tmux www-servers/lighttpd"
DEFPKGS="${DEFPKGS} ${TEMPLPKGS}"

SPEC_SETUP(){
	templBaseConfig
	
	echo "rc_crashed_start=YES" >> $mountDir/etc/rc.conf
	
	cat << 'EOF' > $mountDir/etc/crontab
0 2 * * * root emerge-webrsync >> /var/log/emerge-websync.log && rm /usr/portage/gentoo-*.tar.xz.gpgsig /usr/portage/gentoo-*.tar.xz.md5sum
0 * * * * root /usr/bin/rsync -aP gh-dev::gentoo-binpkg /usr/portage/packages/
EOF
	
	msg "rsync configuration"
	cat << 'EOF' >> $mountDir/etc/rsyncd.conf
[gentoo-portage]
path=/usr/portage
comment=Gentoo Portage
exclude=distfiles/ packages/
EOF

	msg "lighttpd configuration"
	cat << 'EOF' > $mountDir/etc/lighttpd/lighttpd.conf
server.modules += ( "mod_alias" )
alias.url = ( "/packages" => "/usr/portage/packages/" )
server.bind = "10.0.6.203"
EOF
	copyUserGroup "lighttpd"
	
	msg "apt-cacher-ng configuration"
	echo 'PfilePattern: .*' >> $mountDir/etc/apt-cacher-ng/gentoo.conf
	echo 'PassThroughPattern: ^(.*):443$' >> $mountDir/etc/apt-cacher-ng/apt-cacher-ng.conf
	copyUserGroup "apt-cacher-ng"
	
	enableDaemon_def "rsyncd"
	enableDaemon_def "lighttpd"
	enableDaemon_def "apt-cacher-ng"
	
	msg 'replacing nftables'
	cat <<'EOF' > $mountDir/var/lib/nftables/rules-save
#!/sbin/nft -f
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
		tcp dport 80 counter accept comment "accept HTTP"
		tcp dport 873 counter accept comment "accept rsync"
		tcp dport 3142 counter accept comment "accept apt-cache-ng"
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

