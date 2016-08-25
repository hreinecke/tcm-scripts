#!/bin/bash

hba=fileio_0/disk1
iscsi=/sys/kernel/config/target/iscsi
core=/sys/kernel/config/target/core
sec_tpg="secondary_tg_pt_gp"

iqn="iqn.1996-04.de.suse:01:4f89e0ecb85c"
nic0="eth2"
nic1="eth3"

if [ ! -d ${core}/${hba} ] ; then
    tcm_node --fileio=$hba /abuild/target/disk1.img 536870912
fi
[ -d ${core}/${hba} ] || exit 1
if [ ! -d ${core}/${hba}/alua/${sec_tpg} ] ; then
    tcm_node --addtgptgp=$hba secondary_tg_pt_gp
fi

for t in ${iscsi}/${iqn}/tpgt_* ; do
    [ -d ${d} ] || continue
    tpgt=${t##*tpgt_}
    if [ "$tpgt" = "0" ] ; then
	tpgt0=1
    fi
    if [ "$tpgt" = "1" ] ; then
	tpgt1=1
    fi
done
if [ -z "$tpgt0" ] ; then
    lio_node --addtpg=${iqn} 0
fi

if [ -z "$tpgt1" ] ; then
    lio_node --addtpg=${iqn} 1
fi

for p in ${iscsi}/${iqn}/tpgt_0/np/* ; do
    [ -d $p ] || continue
    portal0=${p##*/};
done

for p in ${iscsi}/${iqn}/tpgt_1/np/* ; do
    [ -d $p ] || continue
    portal1=${p##*/};
done

if [ -z "$portal0" ] ; then
    ip0=$(ip addr show dev $nic0 | sed -n 's/ *inet \(.*\)\/[0-9]* brd .*/\1/p')
    lio_node --addnp=${iqn} 0 ${ip0}:3260 || exit 1
fi

if [ -z "$portal1" ] ; then
    ip1=$(ip addr show dev $nic1 | sed -n 's/ *inet \(.*\)\/[0-9]* brd .*/\1/p')
    lio_node --addnp=${iqn} 1 ${ip1}:3260 || exit 1
fi

if [ ! -d ${iscsi}/${iqn}/tpgt_0/lun/lun_0 ] ; then
    lio_node --addlun=${iqn} 0 0 ${ip0}:3260 ${hba}
    lio_node --disableauth=${iqn} 0
    lio_node --permissive=${iqn} 0
    lio_node --enabletpg=${iqn} 0
fi

echo 0 > ${iscsi}/${iqn}/tpgt_0/attrib/demo_mode_write_protect

if [ ! -d ${iscsi}/${iqn}/tpgt_1/lun/lun_0 ] ; then
    lio_node --addlun=${iqn} 1 0 ${ip1}:3260 ${hba}
    lio_node --disableauth=${iqn} 1
    lio_node --permissive=${iqn} 1
    lio_node --enabletpg=${iqn} 1
fi
echo secondary_tg_pt_gp > ${iscsi}/${iqn}/tpgt_1/lun/lun_0/alua_tg_pt_gp
echo 0 > ${iscsi}/${iqn}/tpgt_1/attrib/demo_mode_write_protect

tcm_node --listtgptgps=${hba}
