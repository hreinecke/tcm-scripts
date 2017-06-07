#!/bin/bash

##check if the user has root access
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

set -e
TCM_ROOT=/sys/kernel/config/target
TCM_CONF=/tmp/target.conf

restore_backstore() {
    local attr

    cat $TCM_CONF | while read line ; do
	case "$line" in
	    dir*)
		set -- $line
		[ -d "$TCM_ROOT/$2" ] && continue
		mkdir ${TCM_ROOT}/$2
		;;
	    attr*)
		set -- $line
		shift
		attr=$1
		shift
		[ -f "${TCM_ROOT}/$attr" ] || continue
		if [ "${attr%%_*}" = "core/fileio" ] &&
		    [ "${attr##*/}" = "control" ] ; then
		    val=$(sed -n 's/.*File: *\([^ ]*\) *Size: *\([0-9]*\) .*/fd_dev_name=\1,fd_dev_size=\2/p' ${TCM_ROOT}/${attr%/*}/info)
		elif [ "${attr##*/}" = "alua_lu_gp" ] ; then
		    val=$(sed -n 's/.*Group Alias: \(.*\)/\1/p' ${TCM_ROOT}/$attr)
		else
		    val=$(cat ${TCM_ROOT}/$attr)
		fi
		if [ "$val" != "$*" ] ; then
		    if [ "${attr##*/}" = "alua_access_type" ] ; then
			if [ "$*" = "Implicit and Explicit" ] ; then
			    val=3
			elif [ "$*" = "Explicit" ] ; then
			    val=2
			elif [ "$*" = "Implicit" ] ; then
			    val=1
			else
			    val=0
			fi
		    elif [ "${attr##*/}" = "vpd_unit_serial" ] ; then
			val=$*
			val=${val#T10 VPD Unit Serial Number: }
		    elif [ "${attr##*/}" = "vendor_id" ] ; then
			val=$1
		    else
			val=$*
		    fi
		    echo -n "$val" > ${TCM_ROOT}/$attr
		fi
		;;
	    link*)
		set -- $line
		[ -L "${TCM_ROOT}/$2" ] && continue
		( cd ${TCM_ROOT}/${2%/*}; ln -s $3 ${2##*/} )
		;;
	esac
    done
}

restore_backstore
