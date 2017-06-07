#!/bin/bash

##check if the user has root access
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

gen_sas_address() {
    prefix="naa.6001405"
    uuid=$(uuidgen | sed 's/-//g' | tail --bytes 10)

    echo "${prefix}${uuid}"
}

test_and_set_value() {
    attr=$1
    new_val=$2

    [ -f ${attr} ] || return 0
    read orig_val < ${attr}
    if [ -z "$orig_val" ] || [ ${orig_val} -ne ${new_val} ] ; then
	echo ${new_val} > ${attr}
	if [ $? -ne 0 ] ; then
	    echo "Failed to set ${attr}"
	    exit 1
	fi
    fi
}

imgdir=/dev/shm
img=disk1.img
size=4096
bs=fileio_0
disk=disk1
hba=${bs}/${disk}
loop=/sys/kernel/config/target/loopback
core=/sys/kernel/config/target/core
prim_tpg="default_tg_pt_gp"
sec_tpg="secondary_tg_pt_gp"

#
# configure fileio
#
if [ ! -f ${imgdir}/${img} ] ; then
    [ -d ${imgdir} ] || mkdir ${imgdir}
    dd if=/dev/zero of=${imgdir}/${img} bs=1M count=${size} conv=sparse
fi

if [ ! -d /sys/kernel/config ] ; then
    modprobe target_core_mod
    modprobe tcm_loop
fi

if [ ! -d ${core}/${hba} ] ; then
    [ -d ${core}/${hba} ] || mkdir -p ${core}/${hba}

    echo "Create ${hba} image ${img}"
    imgsize=$(( $size * 1024 * 1024 ))
    echo "fd_dev_name=${imgdir}/${img},fd_dev_size=${imgsize}" > ${core}/${hba}/control
    uuidgen > ${core}/${hba}/wwn/vpd_unit_serial
    echo 1 > ${core}/${hba}/enable
fi

#
# configure ALUA
#
if [ ! -d ${core}/${hba}/alua/${prim_tpg} ] ; then
    echo "Target not configured"
    exit 1
fi

# test_and_set_value ${core}/${hba}/enable 1

test_and_set_value ${core}/${hba}/alua/${prim_tpg}/tg_pt_gp_id 0
test_and_set_value ${core}/${hba}/alua/${prim_tpg}/alua_access_state 0
echo 1 > ${core}/${hba}/alua/${prim_tpg}/alua_access_type
echo 0 > ${core}/${hba}/alua/${prim_tpg}/alua_support_offline
echo 0 > ${core}/${hba}/alua/${prim_tpg}/alua_support_unavailable
test_and_set_value ${core}/${hba}/alua/${prim_tpg}/implicit_trans_secs 30


if [ ! -d ${core}/${hba}/alua/${sec_tpg} ] ; then
    mkdir ${core}/${hba}/alua/${sec_tpg}
    if [ $? -ne 0 ] ; then
	echo "Failed to create ${core}/${hba}/alua/${sec_tpg}"
	exit 1;
    fi
fi

test_and_set_value ${core}/${hba}/alua/${sec_tpg}/tg_pt_gp_id 1
test_and_set_value ${core}/${hba}/alua/${sec_tpg}/alua_access_state 1
echo 1 > ${core}/${hba}/alua/${sec_tpg}/alua_access_type
echo 0 > ${core}/${hba}/alua/${sec_tpg}/alua_support_offline
echo 0 > ${core}/${hba}/alua/${sec_tpg}/alua_support_unavailable
test_and_set_value ${core}/${hba}/alua/${sec_tpg}/implicit_trans_secs 30

#
# configure loopback
#
[ -d ${loop} ] || mkdir ${loop}

num_naa=0
for t in ${loop}/naa.* ; do
    [ -d ${t} ] || continue
    target_address=${t##*/}
    port=$t
    break;
done

if [ -z "$target_address" ] ; then
    target_address=$(gen_sas_address)
    port=${loop}/${target_address}
    if [ ! -d ${port} ] ; then
	echo "Create $port"
	mkdir ${port} || exit 1
    fi
fi

num_tpgt=0
for t in ${port}/tpgt_* ; do
    [ -d ${t} ] || continue
    (( num_tpgt++ ))
done

while [ ${num_tpgt} -lt 2 ] ; do
    t=${port}/tpgt_${num_tpgt}
    if [ ! -d ${t} ] ; then
	echo "Create $t"
	mkdir ${t} || exit 1
    fi
    read nexus < ${t}/nexus 2>/dev/null
    if [ -z "$nexus" ] ; then
	initiator_address=$(gen_sas_address)
	echo "Create nexus $initiator_address"
	echo "${initiator_address}" > ${t}/nexus
	if [ $? -ne 0 ] ; then
	    echo "Failed to create nexus"
	    exit 1
	fi
    fi
    # echo offline > $t/transport_status
    l=${t}/lun/lun_0
    if [ ! -d ${l} ] ; then
	echo "Create ${l}"
	mkdir ${l} || exit 1
    fi
    if [ ! -L ${l}/virtual_scsi_port ] ; then
	echo "Link LUN 0"
	ln -s ${core}/${hba} ${l}/virtual_scsi_port || exit 1
    fi
    if [ $num_tpgt = "1" ] ; then
	echo secondary_tg_pt_gp > ${t}/lun/lun_0/alua_tg_pt_gp
    fi
    # echo online > $t/transport_status
    (( num_tpgt++ ))
done
