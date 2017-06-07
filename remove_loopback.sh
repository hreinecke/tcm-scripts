#!/bin/bash

##check if the user has root access
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

loop=/sys/kernel/config/target/loopback

for wwn in ${loop}/naa* ; do
    [ -d $wwn ] || continue
    for t in ${wwn}/tpgt_* ; do
	[ -d $t ] || continue
	for l in ${t}/lun/lun_* ; do
	    [ -d $l ] || continue
	    rm -f $l/virtual_scsi_port
	    echo "Remove $l"
	    rmdir $l || exit 1
	done
	echo "Remove $t"
	rmdir $t || exit 1
    done
    echo "Remove $wwn"
    rmdir $wwn || exit 1
done

echo "Remove $loop"
rmdir $loop || exit 1

