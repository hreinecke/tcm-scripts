#!/bin/bash

core=/sys/kernel/config/target/core
fc=/sys/kernel/config/target/fc

JSON=$1

apply_attributes () {
    local attrs=$1
    local jsonobj=$2

    for a in ${attrs}/*; do
	attr=${a##*/}
	value=$(cat $a)
	v=$(cat $JSON | jq -c "${jsonobj}.${attr}")
	case ${attr} in
	    alua_access_type)
		if [ "$value" == "Implicit and Explicit" ] ; then
		    value=3
		elif [ "$value" == "Explicit" ] ; then
		    value=2
		elif [ "$value" == "Implicit" ] ; then
		    value=1
		fi
		;;
	    alua_access_status)
		value=$v
		;;
	esac
	if [ "$v" != "null" ] && [ "$value" != "$v" ] ; then
	    echo "Apply $v to $a"
	    echo "$v" > $a
	fi
    done
}

apply_alua () {
    local pname=$1
    local jsonobj=$2
    local j

    j=0
    while [ true ] ; do
	n=$(cat $JSON | jq -c "${jsonobj}.alua_tpgs[$j].name")
	name=$(eval echo $n)
	[ "$name" = "null" ] && break
	echo "Updating ALUA information for $name"
	if [ ! -d "${pname}/alua/${name}" ] ; then
	    mkdir ${pname}/alua/${name} || exit 1
	    id=$(cat $JSON | jq -c "${jsonobj}.alua_tpgs[$j].tg_pt_gp_id")
	    tg_id=$(eval echo $id)
	    if [ "$tg_id" != "null" ] && [ "$tg_id" != "0" ] ; then
		echo $tg_id > ${pname}/alua/${name}/tg_pt_gp_id
	    fi
	fi
	apply_attributes ${pname}/alua/${name} "${jsonobj}.alua_tpgs[$j]"
	(( j++ ))
    done
}
	
find_iblock() {
    local core=$1
    local iblockname=$2
    local iblock

    for iblock in ${core}/iblock_* ; do
	if [ -d ${iblock}/$iblockname ] ; then
	    echo $iblock/$iblockname
	    return
	fi
    done
}

next_iblock() {
    local core=$1
    local iblock
    local i
    local iblocknum=0

    for iblock in ${core}/iblock_* ; do
	[ -d ${iblock} ] || continue
	i=${iblock##*_}
	if [ "$i" -gt "$iblocknum" ] ; then
	    iblocknum=$i
	fi
    done
    (( iblocknum++ ))
    echo $iblocknum
}

setup_iblock() {
    local jsonobj=$1
    local name=$2
    local pblk
    local pname
    local enable

    pname=$(find_iblock $core $name)
    if [ -z "$pname" ] ; then
	iblocknum=$(next_iblock $core)
	pblk=${core}/iblock_$iblocknum
	if ! mkdir ${pblk} 2> /dev/null ; then
	    echo "Cannot create ${pblk}"
	    exit 1
	fi
	pname=${pblk}/${name}
	if ! mkdir ${pname} 2> /dev/null ; then
	    echo "Cannot create ${pname}"
	    exit 1
	fi
    fi

    enable=$(cat ${pname}/enable)
    if [ "$enable" -eq 0 ] ; then
	d=$(cat $JSON | jq -c "${jsonobj}.dev")
	dev=$(eval echo $d)
	path=$(cat ${pname}/udev_path)
	if [ -n "$path" ] && [ "$path" != "$dev" ] ; then
	    rmdir $pname || exit 1
	    mkdir $pname || exit 1
	fi
	if [ -z "$path" ] ; then
	    echo "udev_path=$dev" > ${pname}/control || exit 1
	    echo "$dev" > ${pname}/udev_path
	fi
	w=$(cat $JSON | jq -c "${jsonobj}.wwn")
	wwn=$(eval echo $w)
	if [ "$wwn" != "null" ] ; then
	    echo "$wwn" > ${pname}/wwn/vpd_unit_serial || exit 1
	fi
	echo 1 > ${pname}/enable || exit 1
    fi
    echo "${pname}"
}

gen_fc_port_name() {
    local port_num

    port_num=${1#naa.}
    for i in $(seq 1 2 13) ; do
	j=$(expr $i + 1)
	p=$(echo $port_num | cut --bytes=$i-$j)
	printf "%02x:" $(( 16#$p ))
    done
    p=$(echo $port_num | cut --bytes=15-16)
    printf "%02x\n" $(( 16#$p ))
}

setup_fc_luns() {
    local jsonobj=$1
    local tname=$2
    local l
    local v
    local j
    local idx lname storage_object iblockname backstore alua

    l=0
    while [ true ] ; do
	j="${jsonobj}.luns[$l]"
	v=$(cat $JSON | jq -c "${j}.index")
	idx=$(eval echo $v)
	[ "$idx" = "null" ] && break

	lname=${tname}/lun/lun_${idx}
	if [ ! -d ${lname} ] ; then
	    mkdir ${lname} || exit 1
	fi
	v=$(cat $JSON | jq -c "${j}.storage_object")
	storage_object=$(eval echo $v)
	case $storage_object in
	    /backstores/block/*)
		iblockname=${storage_object##*/}
		for d in ${core}/iblock_* ; do
		    [ -d $d ] || continue
		    if [ -d "$d/$iblockname" ] ; then
			backstore="$d/$iblockname"
		    fi
		done
		;;
	    *)
		backstore=
		;;
	esac
	if [ -n "$backstore" ] ; then
	    v=$(cat $JSON | jq -c "${j}.alias")
	    alias=$(eval echo $v)
	    if [ "$alias" = "null" ] ; then
		alias="mapped_lun"
	    fi
	    ln -s $backstore $lname/$alias
	fi
	v=$(cat $JSON | jq -c "${j}.alua_tg_pt_gp_name")
	alua=$(eval echo $v)
	if [ "$alua" != "null" ] && [ "$alua" != "default_tg_pt_gp" ] ; then
	    echo "$alua" > $tname/alua_tg_pt_gp
	fi
	(( l++ ))
    done
}

setup_fc() {
    local jsonobj=$1
    local wwn
    local t
    local tpgt_id

    if [ ! -d ${fc} ] ; then
	mkdir ${fc} || exit 1
    fi
    wwn=$(gen_fc_port_name $2)
    pname=${fc}/${wwn}
    if [ ! -d ${pname} ] ; then
	mkdir ${pname} || exit 1
    fi

    t=0
    while [ true ] ; do
	jo="${jsonobj}.tpgs[$t]"
	j=$(cat $JSON | jq -c "${jo}")
	[ $(eval echo $j) = "null" ] && return
	tpgt_id=$(expr $t + 1)
	tname="$pname/tpgt_${tpgt_id}"
	if [ ! -d ${tname} ] ; then
	    mkdir ${tname} || exit 1
	fi
	setup_fc_luns $jo $tname
	(( t++ ))
    done
}

i=0
while [ true ] ; do
    jsonobj=".storage_objects[$i]"
    p=$(cat $JSON | jq -c "${jsonobj}.plugin")
    plugin=$(eval echo $p)
    case "$plugin" in
	block)
	    n=$(cat $JSON | jq -c "${jsonobj}.name")
	    name=$(eval echo $n)
	    if [ "$name" != "null" ] ; then
		pname=$(setup_iblock ${jsonobj} $name)
	    fi
	    ;;
	null)
	    break
    esac

    if [ "${pname}" ] ; then
	apply_attributes ${pname}/attrib "${jsonobj}.attributes"
	apply_alua ${pname} "${jsonobj}"
    fi
    (( i++ ))
done

i=0
while [ true ] ; do
    jsonobj=".targets[$i]"
    f=$(cat $JSON | jq -c "${jsonobj}.fabric")
    fabric=$(eval echo $f)
    case "$fabric" in
	tcm_fc)
	    w=$(cat $JSON | jq -c "${jsonobj}.wwn")
	    wwn=$(eval echo $w)
	    if [ "$wwn" != "null" ] ; then
		echo "Setting up FC WWN $wwn"
		setup_fc ${jsonobj} $wwn
	    fi
	    ;;
	null)
	    break
    esac
    (( i++ ))
done
