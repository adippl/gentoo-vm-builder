HOST="rt1"

SPEC_SETUP(){
	echo "setting hostname"
	echo 'hostname="rt1"' > $mountDir/etc/conf.d/hostname
	
	msg "configuring nullmailer"
	echo "$DOMAIN" >  $mountDir/etc/nullmailer/defaultdomain
	echo "$HOST.$DOMAIN" > $mountDir/etc/nullmailer/me
	
	echo "sysctl.conf"
	cat <<'EOF' > $mountDir/etc/sysctl.conf
net.ipv4.ip_forward = 1
net.ipv4.conf.default.rp_filter = 1
EOF	
#net.ipv4.conf.default.rp_filter = 1

	msg "setting up network interface VLANs"

	cat << 'EOF' > $mountDir/etc/conf.d/net
config_eth0=null
vlans_eth0="1 2 3 5 6 9 20 21"
config_eth0_1="192.168.1.20/24"
routes_eth0_1="default via 192.168.1.1"
config_eth0_2="10.0.2.1/24"
config_eth0_3=null
config_eth0_5="10.0.5.1/24"
config_eth0_6="10.0.6.1/24"
config_eth0_9="10.0.9.1/24"
config_eth0_20=null
config_eth0_21=null
EOF
	#disableDaemon_def "net.eth0"
	
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
		tcp dport 22 ip saddr 10.0.0.0/16 counter accept comment "accept SSH"
		counter comment "count dropped packets"
	}
	
	chain output {
		type filter hook output priority filter; policy accept;
		counter comment "count accepted packets"
	}
	
	chain forward {
		type filter hook forward priority filter; policy accept;
		counter comment "count dropped packets"
	}
	
	chain postrouting {
			type nat hook postrouting priority srcnat; policy accept;
		oifname "eth0.1" ip saddr 10.0.0.0/16 counter masquerade comment "SRC-NAT-100"
	}
}
EOF
	}
