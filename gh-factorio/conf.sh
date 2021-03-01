HOST="gh-factorio"
dir=$HOST
VM_IMG_SIZE_GB="4"
CPU="2"
MEM="512"
MAC="76:6d:00:00:00:03"
BRIDGE="brvl6"
TEMPLPKGS="app-vim/vim-tmux"
DEFPKGS="${DEFPKGS} ${TEMPLPKGS}"


SPEC_SETUP(){
	templBaseConfig
	
	msg "configuring static ip $_DISTCCIP on eth0"
	cat << 'EOF' > $mountDir/etc/conf.d/net
config_eth0="10.0.5.209/24"
routes_eth0="default via 10.0.5.1"
dns_servers_eth0="10.0.6.200"
EOF

#	cat << 'EOF' > $mountDir/etc/init.d/factorio
##!/sbin/openrc-run
#
#depend() {
#        need net
#        need localmount
#}
#
#start() {
#	ebegin "starting in tmux"
#	su factorio -c 'tmux -L factorio new -s factorio -d /home/factorio/bin/x64/factorio --start-server /home/factorio/save.zip -c /home/factorio/srv/config.ini '
#}
#
#stop() {
#	su factorio -c "tmux -L factorio send-keys  '/quit' Enter"
#	ebegin 'waiting for server to finish...'
#	while [[ -n $(pidof factorio ) ]]; do 
#		sleep 0.2
#		done
#	ebegin 'server stopped'
#	tmux -S /tmp/tmux-1000/factorio kill-session
#	: ;
#}
#EOF
	
	cat << 'EOF' > $mountDir/etc/init.d/factorio
#!/sbin/openrc-run

depend() {
        need net
        need localmount
}

FAC_SERVER=${SVCNAME##*.}
#name=""
description="factorio server"
command="/home/factorio/bin/x64/factorio"
command_args="--start-server /home/factorio/save.zip"

start(){
	ebegin "Starting $SVCNAME"
	start-stop-daemon --start --exec $command --name $SVCNAME --make-pidfile --pidfile /run/$SVCNAME.pid  --background --stdout-logger "/usr/bin/logger --tag $SVCNAME" -- $command_args
	}

stop(){
	ebegin "Stopping $SVCNAME"
	start-stop-daemon --stop --name $SVCNAME
	}
EOF
	
	chmod +x $mountDir/etc/init.d/factorio
	enableDaemon_def 'factorio'
	
	msg 'adding factorio user'
	echo 'factorio:x:1000:100::/home/factorio:/bin/bash' >> $mountDir/etc/passwd
	echo 'factorio:!:18149:0:99999:7:::' >> $mountDir/etc/shadow
	mkdir -p $mountDir/home/factorio/srv
	mkdir $mountDir/home/factorio/srv/saves
	chown -R 1000:users $mountDir/home/factorio 
	chmod 700 $mountDir/home/factorio 
	
	if ! test -f $dir/factorio-headless-linux64.tar.xz ;then
		warn 'factorio-headless-linux64.tar.xz is missing'
		msg 'downloading server files'
		wget -N -O $dir/factorio-headless-linux64.tar.xz 'https://factorio.com/get-download/stable/headless/linux64'
		fi
	msg 'unpacking factorio server files'
	tar xvJf $dir/factorio-headless-linux64.tar.xz -C $mountDir/home/
	msg 'copying savefile'
	cp $dir/save.zip $mountDir/home/factorio/
	msg 'copying mods'
	tar xvJf $dir/mods.tar.xz -C $mountDir/home/factorio/

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
		tcp dport 22 ip saddr 10.0.0.0/16 counter accept comment "accept local SSH connections"
		udp dport 34197 ip saddr 10.0.0.0/8 counter accept comment "accept factorio connections form subnet"
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

