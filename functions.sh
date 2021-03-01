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
		http_proxy="" PORTAGE_BINHOST="http://gentoo-binhost.lan/packages" ROOT=$mountDir PORTAGE_CONFIGROOT=$mountDir emerge -bgk --with-bdeps=y --keep-going=y -j2 -u $TEMPLPKGS || (echo 'portage returned error code, sleeping for 30 seconds. You can manually kill it if it is serious' && sleep 30)
		fi
	}


