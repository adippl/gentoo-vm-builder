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

	echo "setting up network interface VLANs"
	cat <<'EOF' > $mountDir/etc/conf.d/net
config_eth0=null
vlans_eth0="1 2 3 5 6 9 20 21"
config_eth0_1="192.168.1.20/24"
config_eth0_2="10.0.2.0/24"
config_eth0_3=null
config_eth0_5="10.0.5.0/24"
config_eth0_6="10.0.6.0/24"
config_eth0_9="10.0.9.0/24"
config_eth0_20=null
config_eth0_21=null
EOF	
	}

