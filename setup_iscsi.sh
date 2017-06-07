#!/bin/bash

##check if the user has root access
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

imgdir=/home/kvm
img0=disk0.img
img1=disk1.img
wwid0=5019b2a1-71d7-415e-b2ef-6aebe4ceca20
wwid1=138b7919-e5d2-433f-99da-2ca9f1523538
size=2048
tcm_iscsi=/sys/kernel/config/target/iscsi
core=/sys/kernel/config/target/core
prim_tpg="default_tg_pt_gp"
sec_tpg="secondary_tg_pt_gp"

iqn="iqn.1996-04.de.suse:01:4f89e0ecb85c"
nic0="iscsi0"
nic1="iscsi2"

test_and_set_value() {
    attr=$1
    new_val=$2

    [ -f ${attr} ] || return 0
    read orig_val < ${attr}
    if [ -z "$orig_val" ] || [ ${orig_val} != ${new_val} ] ; then
	echo ${new_val} > ${attr}
	if [ $? -ne 0 ] ; then
	    echo "Failed to set ${attr}"
	    exit 1
	fi
    fi
}

if [ ! -d /sys/kernel/config ] ; then
    modprobe target_core_mod
    modprobe iscsi_core_mod
fi

#
# configure fileio
#
imgnum=0
for img in $img0 $img1 $img2 ; do
    if [ ! -f ${imgdir}/${img} ] ; then
	[ -d ${imgdir} ] || mkdir ${imgdir}
	dd if=/dev/zero of=${imgdir}/${img} bs=1M count=${size} conv=sparse
    fi
    if [ ! -f ${imgdir}/${img} ] ; then
	echo "Image file ${imgdir}/${img} not found"
	exit 1
    fi

    bs=fileio_${imgnum}
    disk=fd_${imgnum}
    hba=${bs}/${disk}
    imgnum=$(expr $imgnum + 1)
    imgsize=$(stat -c "%s" ${imgdir}/${img})
    if [ ! -d ${core}/${hba} ] ; then
	[ -d ${core}/${hba} ] || mkdir -p ${core}/${hba}

	echo "Create ${hba} image ${img}"
	echo "fd_dev_name=${imgdir}/${img},fd_dev_size=${imgsize}" > ${core}/${hba}/control
	if [ "$img" = "$img0" ] ; then
	    wwid=${wwid0}
	elif [ "$img" = "$img1" ] ; then
	    wwid=${wwid1}
	else
	    wwid=${wwid2}
	fi
	echo ${wwid} > ${core}/${hba}/wwn/vpd_unit_serial
	echo 1 > ${core}/${hba}/enable
    fi

    #
    # configure ALUA
    #
    for alua in ${core}/${hba}/alua/${prim_tpg} ${core}/${hba}/alua/${sec_tpc} ; do
	if [ ! -d ${alua} ] ; then
	    echo "Target not configured"
	    exit 1
	fi

	if [ "${alua}" = "${core}/${hba}/alua/${prim_tpg}" ] ; then
	    test_and_set_value ${alua}/tg_pt_gp_id 0
	    test_and_set_value ${alua}/alua_access_state 0
	else
	    test_and_set_value ${alua}/tg_pt_gp_id 16
	    test_and_set_value ${alua}/alua_access_state 1
	fi
	test_and_set_value ${alua}/alua_access_status 0
	test_and_set_value ${alua}/alua_access_type 1
	test_and_set_value ${alua}/alua_support_active_nonoptimized 0
	test_and_set_value ${alua}/alua_support_active_optimized 1
	test_and_set_value ${alua}/alua_support_standby 1
	test_and_set_value ${alua}/alua_support_transitioning 1
	test_and_set_value ${alua}/alua_support_offline 0
	test_and_set_value ${alua}/alua_support_unavailable 0
	test_and_set_value ${alua}/alua_support_write_metadata 0
	test_and_set_value ${alua}/alua_support_lba_dependent 0
	test_and_set_value ${alua}/implicit_trans_secs 30
	test_and_set_value ${alua}/nonop_delay_msecs 100
	test_and_set_value ${alua}/preferred 0
	test_and_set_value ${alua}/trans_delay_msecs 0
    done
done
#
# configure iscsi
#
[ -d ${tcm_iscsi} ] || mkdir ${tcm_iscsi} || exit 1

[ -d ${tcm_iscsi}/${iqn} ] || mkdir ${tcm_iscsi}/${iqn} || exit 1

#
# Map LUNs
#
n=1
for nic in $nic0 $nic1 ; do
    tpgt="tpgt_${n}"
    t="${tcm_iscsi}/${iqn}/${tpgt}"
    [ -d ${t} ] || mkdir ${t} || exit 1

    num_lun=0
    for l in ${core}/fileio_*/fd_* ; do
	[ -d ${l} ] || continue
	[ -d ${t}/lun/lun_${num_lun} ] || mkdir ${t}/lun/lun_${num_lun}
	for ml in ${t}/lun/lun_${num_lun}/* ; do
		if [ -L $ml ] ; then
			mapped_lun=$ml
			break;
		fi
	done
	if [ -n "$mapped_lun" ] ; then
		continue
	else
		ln -s ${l} ${t}/lun/lun_${num_lun}/mapped_lun
	fi
	if [ ${tpgt} == "tpgt_2" ] ; then
		echo ${sec_tpg} > ${t}/lun/lun_${num_lun}/alua_tg_pt_gp
	fi
	(( num_lun++ ))
    done

    ip=$(ip addr show dev $nic | sed -n 's/ *inet \(.*\)\/[0-9]* scope global .*/\1/p')
    if [ -z "$ip" ] ; then
	echo "Missing IP address for if $nic"
	n=$(expr $n + 1)
	continue;
    fi
    np="${t}/np/${ip}:3260"
    [ -d "$np" ] || mkdir $np || exit
    test_and_set_value ${t}/attrib/demo_mode_write_protect 0
    test_and_set_value ${t}/attrib/authentication 0
    test_and_set_value ${t}/enable 1
    n=$(expr $n + 1)
done
