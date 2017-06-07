#!/bin/bash

##check if the user has root access
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

fc=/sys/kernel/config/target/fc

for wwpn in ${fc}/??:??:??:??:??:??:??:?? ; do
    [ -d $wwpn ] || continue
    for t in ${wwpn}/tpgt_* ; do
	[ -d $t ] || continue
	for a in ${t}/acls/* ; do
	    for l in ${a}/lun_* ; do
		for p in $l/* ; do
		    [ -L $p ] || continue
		    echo "Remove acl lun mapping $p"
		    rm -f $p
		done
		echo "Remove acl lun $l"
		rmdir $l || exit 1
	    done
	    echo "Remove acl $a"
	    rmdir $a || exit 1
	done
	for l in ${t}/lun/lun_* ; do
	    [ -d $l ] || continue
	    for p in $l/* ; do
		[ -L $p ] || continue
		echo "Remove lun mapping $p"
		rm -f $p
	    done
	    echo "Remove lun $l"
	    rmdir $l || exit 1
	done
	for p in ${t}/np/* ; do
	    echo "Remove $p"
	    rmdir $p
	done
	echo "Remove $t"
	rmdir $t || exit 1
    done
    echo "Remove $wwpn"
    rmdir $wwpn || exit 1
done

echo "Remove $fc"
rmdir $fc || exit 1

