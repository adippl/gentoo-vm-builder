#!/bin/sh
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

#set -e
unset +e
HOST=${HOST:-"test-vm"}
CPU=${CPU:-"1"}
MEM=${MEM:-"512"}

hexchars="0123456789ABCDEF"
end=$( for i in {1..6} ; do echo -n ${hexchars:$(( $RANDOM % 16 )):1} ; done | sed -e 's/\(..\)/:\1/g' )
randomMAC="52:54:00$end"

NET_BRIDGE=${NET_BRIDGE:-"brvl6"}
NET_MAC=${NET_MAC:-$randomMAC}
source ./libvirtCephSecret.sh
echo HOST $HOST CPU $CPU MEM $MEM

function crmTestRunning(){ 
	crme=$(crm resource status $1 2>&1) ||\
		return 0
	if test "$crme" = "resource $1 is NOT running" ; then
		return 1
	else 
		return 0
		fi;
	}

if test "$REDEPLOY" = "1" ;then
	crm resource stop VD_$HOST
	echo "sleeping for 10 sec for guest to shutdown"
	sleep 10
	#if crmTestRunning VD_$HOST; then
	#	while crmTestRunning VD_$HOST; do
	#		echo waiting for resource VD_$HOST to stop
	#		sleep 1
	#		done
	#	echo "sleeping for 10 sec for guest to shutdown"
	#	sleep 10
	#	fi
	fi

qemu-img convert -p -f raw -O rbd $HOST.img rbd:$cephPool/$HOST ||\
	rbd rm $cephPool/$HOST ||\
	(rbd snap purge $cephPool/$HOST && rbd rm $cephPool/$HOST) &&\
	qemu-img convert -p -f raw -O rbd $HOST.img rbd:$cephPool/$HOST

cp gh-vm-template.xml $HOST.xml
sed -i "s/TEMPL_CEPH_SECRET_REPLACE/$cephSecretId/" $HOST.xml
sed -i "s/TEMPL_CEPH_POOL_REPLACE/$cephPool/" $HOST.xml
sed -i "s/TEMPL_CEPH_IMAGE_REPLACE/$HOST/" $HOST.xml
sed -i "s/TEMPL_NAME_REPLACE/$HOST/" $HOST.xml
sed -i "s/TEMPL_UUID_REPLACE/$(uuidgen)/" $HOST.xml
sed -i "s/TEMPL_NET_BRIDGE_REPLACE/$NET_BRIDGE/" $HOST.xml
sed -i "s/TEMPL_NET_MAC_REPLACE/$NET_MAC/" $HOST.xml
sed -i "s/TEMPL_CPU_REPLACE/$CPU/" $HOST.xml
sed -i "s/TEMPL_MEM_REPLACE/$MEM/" $HOST.xml

cp $HOST.xml $cephShareDomains/

crm configure delete VD_$HOST
crm configure primitive VD_$HOST ocf:heartbeat:VirtualDomain \
	params config="/mnt/cephvm/libvirt/domains/$HOST.xml" hypervisor="qemu:///system" migration_transport=ssh \
	meta allow-migrate=true target-role=Started \
	utilization vcpu=$CPU memory=$MEM \
	op start timeout="120s" \
	op stop timeout="120s" \

