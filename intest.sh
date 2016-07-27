#!/bin/bash

RES=./result
MNT=/mnt/test

rm $RES

_init()
{
	sync
	echo 3 > /proc/sys/vm/drop_caches
}

_dev_test()
{
	mkfs.f2fs /dev/$1
	echo "" >> $RES
	echo -ne "=== $1 ===" >> $RES
	echo "" >> $RES
	nice -n -20 ./tiotest -S -R -f 4096 -b $((1024*1024)) -t 8 -k 1 -k 2 -k 3 -d /dev/$1 #| grep -i "Write        4096 MBs" >> $RES
	nice -n -20 ./tiotest -S -R -f 4096 -b $((1024*1024)) -t 8 -k 0 -k 1 -k 3 -d /dev/$1 #| grep -i "Read         4096 MBs" >> $RES
	nice -n -20 ./tiotest -S -R -f 4096 -b 4096 -r $((1024*1024/4)) -t 8 -k 0 -k 2 -k 3 -d /dev/$1 #| grep -i "Random Write 1024 MBs" >> $RES
	nice -n -20 ./tiotest -S -R -f 4096 -b 4096 -r $((1024*1024/4)) -t 8 -k 0 -k 1 -k 2 -d /dev/$1 #| grep -i "Random Read  1024 MBs" >> $RES
}

__test()
{
	rm -rf $MNT/tiotest*
	_init

	_dev_test pmem0
	_dev_test nvme0n1p1
	_dev_test sdb1
	exit

	i=1
	for i in `seq 0 0`
	do
		cat /sys/kernel/debug/f2fs/status | grep "Utilization:" >> $RES
		df | grep "$MNT" >> $RES

		_init
		echo -ne "$i :" >> $RES
		nice -n -20 ./tiotest -a $i -f 4096 -b $((1024*1024)) -t 1 -k 1 -k 2 -k 3 -d $MNT #| grep -i "Write        4096 MBs" >> $RES
		if [ $? -eq 1 ]; then
			break
		fi
		exit
		_init
		echo -ne "$i :" >> $RES
		nice -n -20 ./tiotest -a $i -f 4096 -b 4096 -r $((1024*1024/4)) -t 1 -k 0 -k 2 -k 3 -d $MNT #| grep -i "Random Write 1024 MBs" >> $RES
		if [ $? -eq 1 ]; then
			break
		fi
		tail -n 4 $RES
	done
}

__test
