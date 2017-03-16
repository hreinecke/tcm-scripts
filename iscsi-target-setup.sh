#!/bin/bash
#
# Theory of operation:
#
# create a veth link with one end into the bridge, and
# the other one to be used a portal interface for the iscsi target
# 

gen_mac_address() {
    # This is the SUSE OUI
    OUI=0x0cfd37
    p1=$(( ($OUI >> 16) & 0xff ))
    p2=$(( ($OUI >>  8) & 0xff ))
    p3=$(( $OUI & 0xff ))

    uuid=$(uuidgen | sed 's/-//g' | tail --bytes 10)

    p4=$(echo $uuid | cut --bytes=1-2)
    p5=$(echo $uuid | cut --bytes=3-4)
    p6=$(echo $uuid | cut --bytes=5-6)

    printf "%02x:%02x:%02x:%s:%s:%s\n" $p1 $p2 $p3 $p4 $p5 $p6
}

MAC_ISCSI_0=0c:fd:37:62:c3:07
MAC_ISCSI_1=0c:fd:37:62:c3:08
IP_ISCSI_0=10.162.198.100
IP_ISCSI_1=10.162.198.101

function create_link() {
    local bridge=$1
    local mac1=$2
    local mac2=$(gen_mac_address)
    local iscsi_if="iscsi$iscsi_num"
    local iscsi_peer
    local iscsi_num=0

    for i in $(ip link show | sed -n 's/.* \(iscsi[0-9]*\)@.*/\1/p') ; do
	num=${i##*iscsi}
	if [ "$num" -gt "$iscsi_num" ] ; then
	    iscsi_num=${num}
	fi
    done
    if [ "$iscsi_num" -gt 0 ] ; then
	iscsi_num=$(( $iscsi_num + 1 ))
    fi
    # Check for existing iscsi interface
    iscsi_if=$(ip link show | grep -B 1 $mac1 | sed -n 's/[0-9]*: \([^:]*\)@.*: .*/\1/p')
    if [ -n "$iscsi_if" ] ; then
	echo $iscsi_if
	return
    fi
    iscsi_if="iscsi$iscsi_num"

    # Peer MAC address is immaterial as it won't show up anywhere
    # The FCoE MAC address shouldn't be changed as the installation
    # might rely on that
    iscsi_num=$(( $iscsi_num + 1 ))
    iscsi_peer="iscsi$iscsi_num"
    ip link add dev $iscsi_if type veth peer name $iscsi_peer
    ip link set addr $mac1 dev $iscsi_if
    ip link set addr $mac2 dev $iscsi_peer
    ip link set mtu 9000 $iscsi_if
    tc qdisc add dev $iscsi_if root pfifo_fast
    ip link set mtu 9000 $iscsi_peer
    tc qdisc add dev $iscsi_peer root pfifo_fast
    ip link set $iscsi_peer master $bridge
    ip link set dev $iscsi_peer up
    ip link set dev $iscsi_if up

    echo "$iscsi_if"
    iscsi_num=$(( $iscsi_num + 1 ))
}

iscsi_if=$(create_link br0 $MAC_ISCSI_0)
if [ -n "$iscsi_if" ] ; then
    ip addr add $IP_ISCSI_0 dev $iscsi_if 
fi

iscsi_if=$(create_link br0 $MAC_ISCSI_1)
if [ -n "$iscsi_if" ] ; then
    ip addr add $IP_ISCSI_1 dev $iscsi_if 
fi
