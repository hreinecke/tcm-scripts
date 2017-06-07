#!/bin/bash

##check if the user has root access
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

TCM_ROOT=/sys/kernel/config/target

shutdown_fcoe() {
    for c in /sys/bus/fcoe/devices/ctlr_* ; do
	[ -d $c ] || continue
	echo 0 > $c/enabled
    done
}

shutdown_fabric() {
    local fabric=$TCM_ROOT/$1

    [[ -d "$fabric" ]] || return
    for p in ${fabric}/* ; do
	[ -d $p ] || continue
	[ "${p##*/}" = "discovery_auth" ] && continue
	for t in ${p}/tpgt_* ; do
	    [ -d $t ] || continue
	    for a in ${t}/acls/* ; do
		[ -d $a ] || continue
		for l in ${a}/lun_* ; do
		    [ -d $l ] || continue
		    for b in $l/* ; do
			[ -L $b ] || continue
			echo "Remove $b"
			rm -f $b
		    done
		    echo "Remove $l"
		    rmdir $l || exit 1
		done
		echo "Remove $a"
		rmdir $a || exit 1
	    done
	    for l in ${t}/lun/lun_* ; do
		[ -d $l ] || continue
		for b in $l/* ; do
		    [ -L $b ] || continue
		    echo "Remove $b"
		    rm -f $b
		done
		echo "Remove $l"
		rmdir $l || exit 1
	    done
	    for n in ${t}/np/* ; do
		[ -d $n ] || continue
		echo "Remove $n"
		rmdir $n
	    done
	    echo "Remove $t"
	    rmdir $t || exit 1
	done
	echo "Remove $p"
	rmdir $p || exit 1
    done
    rmdir $fabric || exit 1
}

shutdown_backstore() {
    local backstore=$TCM_ROOT/core/$1

    for f in ${backstore}_* ; do
	[ -d $f ] || continue
	for d in ${f}/* ; do
	    [ -d $d ] || continue
	    for t in ${d}/alua/* ; do
		[ -d $t ] || continue
		[ ${t##*/} = "default_tg_pt_gp" ] && continue
		echo "Remove $t"
		rmdir $t || exit 1
	    done
	    echo "Remove $d"
	    rmdir $d || exit 1
	done
	echo "Remove $f"
	rmdir $f || exit 1
    done
}

shutdown_fcoe

shutdown_fabric fc
shutdown_fabric iscsi

shutdown_backstore fileio
shutdown_backstore iblock
