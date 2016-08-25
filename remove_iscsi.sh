#!/bin/bash

iscsi=/sys/kernel/config/target/iscsi

for iqn in ${iscsi}/iqn.* ; do
    [ -d $iqn ] || continue
    for t in ${iqn}/tpgt_* ; do
	[ -d $t ] || continue
	for l in ${t}/lun/lun_* ; do
	    [ -d $l ] || continue
	    for p in $l/* ; do
		[ -L $p ] || continue
		echo "Remove $p"
		rm -f $p
	    done
	    echo "Remove $l"
	    rmdir $l || exit 1
	done
	for p in ${t}/np/* ; do
	    echo "Remove $p"
	    rmdir $p
	done
	echo "Remove $t"
	rmdir $t || exit 1
    done
    echo "Remove $iqn"
    rmdir $iqn || exit 1
done

echo "Remove $iscsi"
rmdir $iscsi || exit 1

