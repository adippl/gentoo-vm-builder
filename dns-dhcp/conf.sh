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

HOST="gh-dns-dhcp"
dir="dns-dhcp"
DEFPKGS="${DEFPKGS} net-dns/getdns net-dns/dnsmasq net-misc/dhcp net-ftp/tftp-hpa"

SPEC_SETUP(){
	echo "setting hostname"
	echo 'hostname="gh-dns-dhcp"' > $mountDir/etc/conf.d/hostname
	
	msg "configuring nullmailer"
	echo "$DOMAIN" >  $mountDir/etc/nullmailer/defaultdomain
	echo "$HOST.$DOMAIN" > $mountDir/etc/nullmailer/me
	
	
	echo "setting up network"
	cat <<'EOF' > $mountDir/etc/conf.d/net
config_eth0=null
vlans_eth0="2 3 6 5 9 20 21"
routes_eth0_6="default via 10.0.6.1"
dns_servers_eth0_6="10.0.6.200 127.0.0.1 ::1"
config_eth0_2="10.0.2.200/24"
config_eth0_3="10.0.3.200/24"
config_eth0_5="10.0.5.200/24"
config_eth0_6="10.0.6.200/24"
config_eth0_9="10.0.9.200/24"
config_eth0_20="10.0.20.200/24"
config_eth0_21="10.0.21.200/24"
EOF
	
	msg "writing dnsmasq config"
	cat <<'EOF' > $mountDir/etc/dnsmasq.conf
no-hosts
addn-hosts=/etc/dnsmasq.conf.hosts
no-resolv
proxy-dnssec
server=::1#53000
server=127.0.0.1#53000
EOF
	
	msg "copying dnsmasq.conf.hosts"
	cp $dir/dnsmasq.conf.hosts $mountDir/etc/dnsmasq.conf.hosts
	enableDaemon_def "dnsmasq"
	
	
	msg "copying dhcp config"
	cp  $dir/dhcpd.conf $mountDir/etc/dhcp/dhcpd.conf
	enableDaemon_def "dhcpd"
	
	msg "writing stubby config"
	cat <<'EOF' > $mountDir/etc/stubby/stubby.yml
resolution_type: GETDNS_RESOLUTION_STUB
dns_transport_list:
  - GETDNS_TRANSPORT_TLS
tls_authentication: GETDNS_AUTHENTICATION_REQUIRED
tls_query_padding_blocksize: 128
edns_client_subnet_private : 1
round_robin_upstreams: 1
idle_timeout: 10000
listen_addresses:
  - 127.0.0.1@53000
  - 0::1@53000
upstream_recursive_servers:
  - address_data: 145.100.185.15
    tls_auth_name: "dnsovertls.sinodun.com"
    tls_pubkey_pinset:
      - digest: "sha256"
        value: 62lKu9HsDVbyiPenApnc4sfmSYTHOVfFgL3pyB+cBL4=
  - address_data: 145.100.185.16
    tls_auth_name: "dnsovertls1.sinodun.com"
    tls_pubkey_pinset:
      - digest: "sha256"
        value: cE2ecALeE5B+urJhDrJlVFmf38cJLAvqekONvjvpqUA=
  - address_data: 185.49.141.37
    tls_auth_name: "getdnsapi.net"
    tls_pubkey_pinset:
      - digest: "sha256"
        value: foxZRnIh9gZpWnl+zEiKa0EJ2rdCGroMWm02gaxSc9Q=
  - address_data: 2001:610:1:40ba:145:100:185:15
    tls_auth_name: "dnsovertls.sinodun.com"
    tls_pubkey_pinset:
      - digest: "sha256"
        value: 62lKu9HsDVbyiPenApnc4sfmSYTHOVfFgL3pyB+cBL4=
  - address_data: 2001:610:1:40ba:145:100:185:16
    tls_auth_name: "dnsovertls1.sinodun.com"
    tls_pubkey_pinset:
      - digest: "sha256"
        value: cE2ecALeE5B+urJhDrJlVFmf38cJLAvqekONvjvpqUA=
  - address_data: 2a04:b900:0:100::38
    tls_auth_name: "getdnsapi.net"
    tls_pubkey_pinset:
      - digest: "sha256"
        value: foxZRnIh9gZpWnl+zEiKa0EJ2rdCGroMWm02gaxSc9Q=
  - address_data: 1.1.1.1
    tls_auth_name: "cloudflare-dns.com"
  - address_data: 1.0.0.1
    tls_auth_name: "cloudflare-dns.com"
  - address_data: 89.233.43.71
    tls_auth_name: "unicast.censurfridns.dk"
    tls_pubkey_pinset:
      - digest: "sha256"
        value: wikE3jYAA6jQmXYTr/rbHeEPmC78dQwZbQp6WdrseEs=
EOF
	enableDaemon_def "stubby"
	
	
	msg 'replacing default nftables'
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
		ip saddr != 10.0.0.0/8 counter drop comment "drop all outside of lan"
		tcp dport 22 ip saddr 10.0.0.0/16 counter accept comment "accept SSH"
		tcp dport 53 ip saddr 10.0.0.0/8 counter accept comment "accept dnsmasq"
		udp dport 53 ip saddr 10.0.0.0/8 counter accept comment "accept dnsmasq"
		udp dport 69 ip saddr 10.0.0.0/16 counter accept comment "accept TFTP"
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
	msg "configuring in.tftp"
	cat <<'EOF' > $mountDir/etc/conf.d/in.tftpd
INTFTPD_PATH="/tftp/"
INTFTPD_OPTS="-R 4096:32767 -s ${INTFTPD_PATH}"
EOF
	msg "adding TFTP files"
	mkdir $mountDir/var/tftp/
	cp -r $dir/tftp/* $mountDir/var/tftp/
	enableDaemon_def "in.tftpd"
	#msg "unpacking kernel and initramfs for tftp server"
	
	warn "manually copying users and groups from host"
	copyUserGroup "dnsmasq"
	copyUserGroup "stubby"
	copyUserGroup "dhcp"
	
	}

