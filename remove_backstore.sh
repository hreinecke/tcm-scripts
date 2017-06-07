#!/bin/bash

##check if the user has root access
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

core=/sys/kernel/config/target/core

for f in ${core}/fileio_* ${core}/iblock_* ; do
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

