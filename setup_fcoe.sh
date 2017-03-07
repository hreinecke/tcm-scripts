#!/bin/bash

gen_sas_address() {
    prefix="naa.6001405"
    uuid=$(uuidgen | sed 's/-//g' | tail --bytes 10)

    echo "${prefix}${uuid}"
}

gen_fc_port_name() {
    port_num=$1

    for i in $(seq 3 2 15) ; do
	j=$(expr $i + 1)
	p=$(echo $port_num | cut --bytes=$i-$j)
	printf "%02x:" $(( 16#$p ))
    done
    p=$(echo $port_num | cut --bytes=17-18)
    printf "%02x\n" $(( 16#$p ))
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

imgdir=/home/kvm
img0=sles-mpath-0.img
img1=sles-mpath-1.img
img2=sles-mpath-2.img
wwid0=2969579b-c1a2-4181-a963-fe7c57bed635
wwid1=3d24a64c-9cd6-4552-8a3e-15bb2a823e65
wwid2=a59a43bd-1ba7-494c-be4c-fe6ddd8d6643
size=2048
tcm_fc=/sys/kernel/config/target/fc
core=/sys/kernel/config/target/core
prim_tpg="default_tg_pt_gp"
sec_tpg="secondary_tg_pt_gp"

target_0=20:00:0c:fd:37:d4:44:7a
target_1=20:00:0c:fd:37:d4:44:7b
initiator_0=20:00:0c:fd:37:04:1a:1e
initiator_1=20:00:0c:fd:37:04:1a:1f

if [ ! -d /sys/kernel/config ] ; then
    modprobe target_core_mod
    modprobe tcm_fc
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
    echo 0 > ${core}/${hba}/alua/${prim_tpg}/alua_support_lba_dependent
    test_and_set_value ${core}/${hba}/alua/${prim_tpg}/implicit_trans_secs 30

    if [ ! -d ${core}/${hba}/alua/${sec_tpg} ] ; then
	mkdir ${core}/${hba}/alua/${sec_tpg}
	if [ $? -ne 0 ] ; then
	    echo "Failed to create ${core}/${hba}/alua/${sec_tpg}"
	    exit 1
	fi
    fi

    test_and_set_value ${core}/${hba}/alua/${sec_tpg}/tg_pt_gp_id 16
    test_and_set_value ${core}/${hba}/alua/${sec_tpg}/alua_access_state 1
    echo 1 > ${core}/${hba}/alua/${sec_tpg}/alua_access_type
    echo 0 > ${core}/${hba}/alua/${sec_tpg}/alua_support_offline
    echo 0 > ${core}/${hba}/alua/${sec_tpg}/alua_support_unavailable
    echo 0 > ${core}/${hba}/alua/${sec_tpg}/alua_support_lba_dependent
    test_and_set_value ${core}/${hba}/alua/${sec_tpg}/implicit_trans_secs 30
done

#
# configure fcoe
#
[ -d ${tcm_fc} ] || mkdir ${tcm_fc}

#
# Map LUNs
#
for t in /sys/bus/fcoe/devices/ctlr_*/host* ; do
    [ -d ${t} ] || continue
    host=${t##*/}
    [ -d ${t}/fc_host/${host} ] || continue
    port_name=$(cat ${t}/fc_host/${host}/port_name)
    fc_port_name=$(gen_fc_port_name $port_name)
    [ -d ${tcm_fc}/${fc_port_name} ] || mkdir ${tcm_fc}/${fc_port_name}
    t=${tcm_fc}/${fc_port_name}/tpgt_1
    [ -d ${t} ] || mkdir ${t}
    num_lun=0
    for l in ${core}/fileio_*/fd_* ; do
	[ -d ${l} ] || continue
	[ -d ${t}/lun/lun_${num_num} ] || mkdir ${t}/lun/lun_${num_lun}
	ln -s ${l} ${t}/lun/lun_${num_lun}/mapped_lun 2> /dev/null
	if [ ${fc_port_name} == ${target_1} ] ; then
	    echo ${sec_tpg} > ${t}/lun/lun_${num_lun}/alua_tg_pt_gp
	fi
	(( num_lun++ ))
    done
    #
    # Map initiator ACLs
    #
    if [ ${fc_port_name} == ${target_0} ] ; then
	fc_initiator_name=${initiator_0}
    else
	fc_initiator_name=${initiator_1}
    fi
    acl=${t}/acls/${fc_initiator_name}
    if [ ! -d ${acl} ] ; then
	mkdir ${acl}
    fi
    for l in ${t}/lun/* ; do
	[ -d ${l} ] || continue
	lun_acl=${acl}/${l##*/}
	[ -d ${lun_acl} ] || mkdir ${lun_acl}
	if [ ! -L ${lun_acl}/mapped_lun ] ; then
	    echo "Map ${l##*/}"
	    ln -s ${l} ${lun_acl}/mapped_lun
	fi
    done
done
