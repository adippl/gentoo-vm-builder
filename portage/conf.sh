HOST="gh-portage"
VM_IMG_SIZE_GB="30"
DEFPKGS="${DEFPKGS} net-misc/apt-cacher-ng"

SPEC_SETUP(){
	echo "setting hostname"
	echo 'hostname="gh-portage"' > $mountDir/etc/conf.d/hostname
	
	msg "configuring nullmailer"
	echo "$DOMAIN" >  $mountDir/etc/nullmailer/defaultdomain
	echo "$HOST.$DOMAIN" > $mountDir/etc/nullmailer/me
	

	cat << 'EOF' > $mountDir/etc/crontab
0 2 * * * root emerge-webrsync >> /var/log/emerge-websync.log && rm /usr/portage/gentoo-*.tar.xz.gpgsig /usr/portage/gentoo-*.tar.xz.md5sum
EOF

	cat << 'EOF' >> $mountDir/etc/rsyncd.conf
[gentoo-portage]
path=/usr/portage
comment=Gentoo Portage
exclude=distfiles/ packages/
EOF


	echo 'apt-cacher-ng:x:999:249:added by portage for apt-cacher-ng:/dev/null:/sbin/nologin' >> $mountDir/etc/passwd
	echo 'apt-cacher-ng:!:18667::::::' >> $mountDir/etc/shadow
	echo 'apt-cacher-ng:x:249:' >> $mountDir/etc/group

	echo 'PfilePattern: .*' >> $mountDir/etc/apt-cacher-ng/gentoo.conf
	echo 'PassThroughPattern: ^(.*):443$' >> $mountDir/etc/apt-cacher-ng/apt-cacher-ng.conf
	
	enableDaemon_def "rsyncd"
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

