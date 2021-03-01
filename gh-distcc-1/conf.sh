HOST="gh-distcc-1"
DEFPKGS="${DEFPKGS} app-emulation/docker"
dir=gh-distcc
TMPL_VM_IMG_SIZE_GB="4"
CPU="8"
MEM="2048"
BRIDGE="brvl6"
TEMPLPKGS="sys-devel/distcc"
DEFPKGS="${DEFPKGS} ${TEMPLPKGS}"

_DISTCCIP=${DISTCCIP:-"10.0.6.220/24"}

SPEC_SETUP(){
	templBaseConfig
	msg "configuring static ip $_DISTCCIP on eth0"
	cat << 'EOF' > $mountDir/etc/conf.d/net
routes_eth0="default via 10.0.6.1"
dns_servers_eth0="10.0.6.200"
EOF
	echo "config_eth0=\"$_DISTCCIP\"" >> $mountDir/etc/conf.d/net
	
	msg "configuring distcc"
	sed -i '/allow/d' $mountDir/etc/conf.d/distccd
	echo "DISTCCD_OPTS=\"${DISTCCD_OPTS} --allow $_DISTCCIP\"" >> $mountDir/etc/conf.d/distccd
	echo "DISTCCD_OPTS=\"${DISTCCD_OPTS} --listen 10.0.0.0/16\"" >> $mountDir/etc/conf.d/distccd

	warn "copying distcc user and group from host"
	copyUserGroup "distcc"
	
	enableDaemon_def distccd
	}
