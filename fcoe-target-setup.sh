#!/bin/bash
#
# Theory of operation:
#
# create a veth link with one end into the bridge, and
# a VLAN interface on the other end to be used as
# interface for the FCoE target.
# We could drop the VLAN interface, but the iPXE won't
# work properly (it still assumes that FCoE is always
# running on VLAN interfaces) and the FCoE traffic might
# be routed by the bridge into the actual network.
# So stick to VLANs for the time being.
#
# For multipathing we're creating two veth links with
# different VLANs
# 

# Please adjust
MAC_FCOE_0=0c:fd:37:d4:44:7a
MAC_FCOE_1=0c:fd:37:d4:44:7b
VLAN_0=210
VLAN_1=200

##check if the user has root access
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

##check if the FCoE module is loaded, otherwise terminate
if ! lsmod | grep "fcoe" &> /dev/null; then
    echo "FCoE module not found, please load the FCoE module first using \"modprobe fcoe"\"
    exit 1
fi

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

function create_link() {
    local bridge=$1
    local mac1=$2
    local mac2=$(gen_mac_address)
    local vlan=$3
    local fcoe_if="fcoe$fcoe_num"
    local fcoe_peer
    local fcoe_num=0

    for i in $(ip link show | sed -n 's/.* \(fcoe[0-9]*\)@.*/\1/p') ; do
	num=${i##*fcoe}
	if [ "$num" -gt "$fcoe_num" ] ; then
	    fcoe_num=${num}
	fi
    done
    if [ "$fcoe_num" -gt 0 ] ; then
	fcoe_num=$(( $fcoe_num + 1 ))
    fi
    # Check for existing fcoe interface
    fcoe_if=$(ip link show | grep -B 1 $mac1 | sed -n 's/[0-9]*: \([^:]*\)@.*: .*/\1/p')
    if [ -n "$fcoe_if" ] ; then
	for i in $fcoe_if ; do
	    if ip -d link show dev $i | grep -q vlan ; then
		echo $i
		return
	    fi
	done
	return
    fi
    fcoe_if="fcoe$fcoe_num"

    # Peer MAC address is immaterial as it won't show up anywhere
    # The FCoE MAC address shouldn't be changed as the installation
    # might rely on that
    fcoe_num=$(( $fcoe_num + 1 ))
    fcoe_peer="fcoe$fcoe_num"
    ip link add dev $fcoe_if type veth peer name $fcoe_peer
    ip link set addr $mac1 dev $fcoe_if
    ip link set addr $mac2 dev $fcoe_peer
    ip link set mtu 9000 $fcoe_if
    tc qdisc add dev $fcoe_if root pfifo_fast
    ip link set mtu 9000 $fcoe_peer
    tc qdisc add dev $fcoe_peer root pfifo_fast
    ip link set $fcoe_peer master $bridge
    ip link add link $fcoe_if name $fcoe_if.$vlan type vlan id $vlan
    ip link set mtu 9000 $fcoe_if.$vlan
    tc qdisc add dev $fcoe_if.$vlan root pfifo_fast
    ip link set dev $fcoe_peer up
    ip link set dev $fcoe_if up

    echo "$fcoe_if.$vlan"
    fcoe_num=$(( $fcoe_num + 1 ))
}

function check_fcoe() {
    local fcoe_if=$1

    for c in /sys/bus/fcoe/devices/ctlr_* ; do
	[ -d "$c" ] || continue
	devpath=$(cd -P $c; cd ..; echo $PWD)
	ifname=${devpath##*/}
	if [ "$ifname" = "$fcoe_if" ] ; then
	    echo "${c##*/}"
	    return
	fi
    done
}

function create_target() {
    local fcoe_mac=$1
    local fcoe_wwn="20:00:$fcoe_mac"

    [ -d /sys/kernel/config/target ] || modprobe target_core_mod
    if [ ! -d /sys/kernel/config/target/fc ] ; then
	modprobe tcm_fc
	mkdir /sys/kernel/config/target/fc
    fi
    tcm_fc=/sys/kernel/config/target/fc/${fcoe_wwn}
    if [ ! -d "$tcm_fc" ] ; then
	mkdir $tcm_fc || exit 1
    fi
    if [ ! -d ${tcm_fc}/tpgt_1 ] ; then
	mkdir ${tcm_fc}/tpgt_1 || exit 1
    fi
}

fcoe_if=$(create_link br0 $MAC_FCOE_0 $VLAN_0)
if [ -n "$fcoe_if" ]; then
    ctlr=$(check_fcoe $fcoe_if)
    [ -z "$ctlr" ] && echo $fcoe_if > /sys/bus/fcoe/ctlr_create
    ctlr=$(check_fcoe $fcoe_if)
    if [ -z "ctlr" ] ; then
	echo "Cannot create FCoE device $fcoe_if"
	exit 1
    fi
    echo "vn2vn" > /sys/bus/fcoe/devices/$ctlr/mode
    create_target $MAC_FCOE_0
fi

fcoe_if=$(create_link br0 $MAC_FCOE_1 $VLAN_1)
if [ -n "$fcoe_if" ]; then
    ctlr=$(check_fcoe $fcoe_if)
    [ -z "$ctlr" ] && echo $fcoe_if > /sys/bus/fcoe/ctlr_create
    ctlr=$(check_fcoe $fcoe_if)
    if [ -z "ctlr" ] ; then
	echo "Cannot create FCoE device $fcoe_if"
	exit 1
    fi
    echo "vn2vn" > /sys/bus/fcoe/devices/$ctlr/mode
    create_target $MAC_FCOE_1
fi
