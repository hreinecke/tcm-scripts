#!/bin/bash

TCM_ROOT=/sys/kernel/config/target
TCM_CONF=/tmp/target.conf

print_fabric() {
    local dir=$1

    for a in $(find $dir -name statistics -prune -o -print) ; do
	attr=${a##$TCM_ROOT/}
	if [ -L $a ] ; then
	    echo "link ${attr} $(readlink $a)"
	elif [ -f $a ] ; then
	    [ $(stat -c '%a' $a) = "200" ] && continue
	    case $a in
		*alua*members)
		    continue
		    ;;
		*alua*alua_access_status)
		    continue
		    ;;
		*pr/res_holder)
		    continue
		    ;;
		*pr/res_pr_registered_i_pts)
		    continue
		    ;;
		*pr/res_aptpl_metadata)
		    continue
		    ;;
	    esac
	    if [ "${attr%%_*}" = "core/fileio" ] ; then
		if [ "${attr##*/}" = "info" ] ; then
		    continue
		fi
		if [ "${attr##*/}" = "enable" ] ; then
		    continue
		fi
	    fi
	    if [ "${attr##*/}" = "hba_info" ] ; then
		continue
	    fi
	    if [ "${attr##*/}" = "alua_lu_gp" ] ; then
		val=$(sed -n 's/.*Group Alias: \(.*\)/\1/p' $a)
		echo "attr ${attr} $val"
		continue
	    fi
	    if [ "${attr##*/}" = "alua_tg_pt_gp" ] ; then
		val=$(sed -n 's/.*Port Alias: \(.*\)/\1/p' $a)
		echo "attr ${attr} $val"
		continue
	    fi
	    if [ "${attr##*/}" = "vendor_id" ] ; then
		val=$(sed -n 's/.*Identification: *\(.*\)/\1/p' $a)
		echo "attr ${attr} $val"
		continue
	    fi
	    val=$(cat $a)
	    if [ -n "$val" ] ; then
		echo "attr ${attr} $val"
	    fi
	else
	    echo "dir ${attr}"
	    
	    case ${attr##*/} in
		fd_*)
		    echo -n "attr ${attr}/control "
		    sed -n 's/.*File: *\([^ ]*\) *Size: *\([0-9]*\) .*/fd_dev_name=\1,fd_dev_size=\2/p' ${a}/info
		    enable=$(cat ${a}/enable)
		    echo "attr ${attr}/enable $enable"
		    ;;
	    esac	
	fi
    done
}

print_fabric $TCM_ROOT/core
for tcm in $TCM_ROOT/iscsi/*/tpgt_* $TCM_ROOT/fc/*/tpgt_* ; do
    [ -d $tcm ] || continue
    tpgt=${tcm##$TCM_ROOT/}
    port=${tpgt%/*}
    fabric=${port%/*}
    echo "dir $fabric"
    echo "dir $port"
    echo "dir $tpgt"
    print_fabric $tcm/attrib
    print_fabric $tcm/param
    print_fabric $tcm/lun
    print_fabric $tcm/auth
    print_fabric $tcm/acls
done
