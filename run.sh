#!/bin/sh

#VER=f2fs-3.18
#VER=f2fs-3.10
VER=f2fs
DEV=sdb1
TESTDIR=/mnt/test

truncate --size 0 /var/log/kern.log

_reload_f2fs()
{
	umount /mnt/*
	rmmod f2fs
	insmod ~/$VER/fs/f2fs/f2fs.ko
}

FS=f2fs

_check()
{
	umount /mnt/*
#	mkfs.$FS /dev/sdb1
#	mkfs.$FS /dev/sdc1
#	mkfs.$FS -O encrypt /dev/sdb1
#	mkfs.$FS -O encrypt /dev/sdc1
#	t="tests/generic/221 tests/generic/223 tests/generic/224"
#	t="tests/generic/068 tests/generic/069 tests/generic/070"
#	t="tests/generic/016 tests/genenric/014 tests/generic/019 tests/generic/027"
#	t="tests/generic/224 tests/generic/311"
#	t="tests/generic/236 tests/generic/237"
#	t="tests/generic/058"
#	t="tests/generic/141 tests/generic/169 tests/generic/177"
#	t="tests/generic/169 tests/generic/177"
#	t="$t tests/f2fs/001"
#	t="$t tests/generic/133"
#	t="$t tests/generic/064"
#	t="$t tests/generic/092"
#	t="$t tests/generic/094"
#	t="$t tests/generic/123"
#	t="$t tests/generic/124"
#	t="$t tests/generic/125"
#	t="$t tests/generic/126"
#	t="$t tests/generic/322"
#	t="tests/generic/128"
#	t="tests/generic/080 tests/generic/081"
#	t="tests/f2fs/001"
	./check -x quota,clone,dedupe $t
}

_debug_check()
{
	umount /mnt/*
#	mkfs.$FS /dev/sdb1
#	mkfs.$FS /dev/sdc1
	mkfs.$FS -O encrypt /dev/sdb1
	mkfs.$FS -O encrypt /dev/sdc1
#	t="tests/generic/221 tests/generic/223 tests/generic/224"
#	t="tests/generic/068 tests/generic/069 tests/generic/070"
#	t="tests/generic/016 tests/genenric/014 tests/generic/019 tests/generic/027"
#	t="tests/generic/224 tests/generic/311"
#	t="tests/generic/236 tests/generic/237"
	t="tests/generic/066"
	for i in `seq 10 65`
	do
		t="tests/generic/0$i"
		cat /var/log/kern.log >> ./testres
		./run.sh reload
		umount /mnt/*
		echo $t >> ./testres
		./check -X tests/generic/017 $t
	done
}

_fs_opts()
{
	echo 1000 > /sys/fs/f2fs/$DEV/gc_max_sleep_time
	echo 1000 > /sys/fs/f2fs/$DEV/gc_min_sleep_time
	echo 10 > /sys/fs/f2fs/$DEV/gc_idle
	echo 10000 > /sys/fs/f2fs/$DEV/gc_no_gc_sleep_time
	echo 2 > /sys/fs/f2fs/$DEV/cp_interval
	echo 5 > /sys/fs/f2fs/$DEV/idle_interval
	echo 10 > /sys/fs/f2fs/$DEV/ram_thresh
	echo 2024 > /sys/fs/f2fs/$DEV/reclaim_segments

	rand=`shuf -i 1000-2000 -n 1`
	echo $rand > /sys/fs/f2fs/fault_injection/inject_rate
	echo 127 > /sys/fs/f2fs/fault_injection/inject_type
}

_mount()
{
	#mount -t f2fs /dev/$DEV -o no_heap,background_gc=off,active_logs=2,discard $TESTDIR
	#mount -t f2fs /dev/$DEV -o background_gc=sync,active_logs=6,discard $TESTDIR
	mount -t f2fs /dev/$DEV -o background_gc=on,active_logs=6,discard $TESTDIR
#	mount -t f2fs /dev/$DEV -o background_gc=off,active_logs=6,discard $TESTDIR
}

_error()
{
	# CP blkaddr
	dd if=/dev/zero of=/dev/$DEV bs=4 seek=275 count=1
	_mount
	umount /mnt/*
}

_init()
{
	_reload_f2fs
	umount /mnt/*
	mkfs.f2fs -O encrypt /dev/$DEV
	_mount
	mkdir $TESTDIR/test
	_fs_opts
}

_init_crypt()
{
	_reload_f2fs
	umount /mnt/*
	mkfs.f2fs -O encrypt /dev/$DEV
	_error
	_mount
	echo foo | e4crypt add_key -S 0x12 $TESTDIR
	mkdir $TESTDIR/test
	_fs_opts
}

cur=0
_rm_50()
{
	for i in `seq 0 10`
	do
		idx=`printf '%x' $((($cur + $i)%20))`
		rm -rf "$TESTDIR/test/p$idx"
	done
	cur=$(($cur + 1))
}

por_fsstress()
{
	while true; do
		ltp/fsstress -x "echo 3 > /proc/sys/vm/drop_caches" -X 10 -r -f fsync=8 -f sync=0 -f write=4 -f dwrite=2 -f truncate=6 -f allocsp=0 -f bulkstat=0 -f bulkstat1=0 -f freesp=0 -f zero=1 -f collapse=1 -f insert=1 -f resvsp=0 -f unresvsp=0 -S t -p 20 -n 200000 -d $TESTDIR/test &
		sleep 5
		src/godown -n $TESTDIR
		killall fsstress
		echo 3 > /proc/sys/vm/drop_caches
		fsck.f2fs /dev/$DEV | grep -q -e "Fail"
		if [ $? -eq  0 ]; then
			exit
		fi
		sleep 1
		umount $TESTDIR
		echo 3 > /proc/sys/vm/drop_caches
		fsck.f2fs /dev/$DEV
		_mount
		_rm_50
		_fs_opts
	done
}

_fsstress()
{
	while true; do
		#ltp/fsstress -x "echo 3 > /proc/sys/vm/drop_caches && sleep 1" -X 10 -r -S t -p 10 -n 1000000 -d $TESTDIR/test
		ltp/fsstress -x "echo 3 > /proc/sys/vm/drop_caches" -X 1000 -r -f fsync=0 -f sync=0 -f write=10 -f dwrite=4 -f truncate=6 -f allocsp=0 -f bulkstat=0 -f bulkstat1=0 -f freesp=0 -f zero=1 -f collapse=1 -f insert=1 -f resvsp=0 -f unresvsp=0 -f link=1 -S t -p 10 -n 200000 -d $TESTDIR/test
		#ltp/fsstress -r -f fsync=0 -f sync=0 -f write=10 -f dwrite=4 -f truncate=6 -f allocsp=0 -f bulkstat=0 -f bulkstat1=0 -f freesp=0 -f zero=1 -f collapse=1 -f insert=1 -f resvsp=0 -f unresvsp=0 -f link=1 -S t -p 10 -n 200000 -d $TESTDIR/test
		#ltp/fsstress -x "echo 3 > /proc/sys/vm/drop_caches" -X 1000 -r -z -f chown=1 -f creat=4 -f dread=1 -f dwrite=1 -f fallocate=1 -f fdatasync=1 -f fiemap=1 -f fsync=1 -f getattr=1 -f getdents=1 -f link=1 -f mkdir=0 -f mknod=1 -f punch=1 -f zero=1 -f collapse=1 -f insert=1 -f read=1 -f readlink=1 -f rename=1 -f rmdir=1 -f setxattr=1 -f stat=1 -f symlink=2 -f truncate=2 -f unlink=2 -f write=4 -S t -p 10 -n 10000 -d $TESTDIR/test
		umount $TESTDIR
		fsck.f2fs /dev/$DEV
		_mount
		rm -rf $TESTDIR/*
		umount $TESTDIR
		fsck.f2fs /dev/$DEV
		_mount
		_fs_opts
	done
}

_watch()
{
	watch -n .2 tail -n +$(grep -m 1 -n sdb2 /sys/kernel/debug/f2fs/status |cut -f1 -d:) /sys/kernel/debug/f2fs/status
#	while true
#	do
#		f2fstat -i 10 -p /dev/$1
#		sleep 1
#	done
}

_reset()
{
	umount /mnt/*
	ls /dev/sg*

	echo -n "reset for write_ptr, sg4? [sg4] "
	read sg
	if [ $sg -z ]; then
		sg=sg4
	fi

	zbc_reset_write_ptr /dev/$sg -1

	ls /dev/sd*

	echo -n "reset for /dev/sdd? [sdd] "
	read sdd
	if [ $sdd -z ]; then
		sdd=sdd
	fi

	readlink /sys/block/$sdd

	echo -n "host number? [6] "
	read host
	if [ $host -z ]; then
		host=6
	fi

	echo $host > /sys/block/$sdd/device/delete
	echo "- - -" > /sys/class/scsi_host/host$host/scan

	sleep 2
	ls /dev/sd*

	echo -n "go mkfs [sdd]? "
	read sdd 
	if [ $sdd -z ]; then
		sdd=sdd
	fi
	umount /mnt/*
	mkfs.f2fs -m /dev/$sdd

	echo 1 > /sys/block/$sdd/device/queue_depth

	echo -n "go mount? "
	read go
	_reload f2fs
	mount -t f2fs /dev/$sdd $TESTDIR

	echo -n "go fsstress? "
	read go
	ltp/fsstress -x "echo 3 > /proc/sys/vm/drop_caches" -X 10 -r -f fsync=8 -f sync=0 -f write=4 -f dwrite=2 -f truncate=6 -f allocsp=0 -f bulkstat=0 -f bulkstat1=0 -f freesp=0 -f zero=1 -f collapse=1 -f insert=1 -f resvsp=0 -f unresvsp=0 -S t -p 20 -n 200000 -d $TESTDIR/test
}

case "$1" in
reload)
	_reload_f2fs
	#mkfs.f2fs -O encrypt /dev/$DEV
	#mkfs.f2fs -a 0 -s 20 /dev/$DEV
	mkfs.f2fs -t 0 -O encrypt /dev/$DEV
	#_error
	_mount
	_fs_opts
#	echo foo | e4crypt add_key -S 0x12 $TESTDIR
	;;
xfstests)
	mkfs.f2fs /dev/ram0
	mkfs.f2fs /dev/ram1
	cp local.config.ram local.config
	_check
	cp local.config.noenc local.config
	_check
	cp local.config.enc local.config
	_check
	;;
fsstress)
	_init
	_fsstress
	;;
por_fsstress)
	por_fsstress
	;;
test)
	umount /mnt/*
	mkfs.f2fs -O encrypt /dev/$DEV
	_mount
	mkdir $TESTDIR/test
	echo foo | e4crypt add_key -S 0x12 $TESTDIR
	_fs_opts
	ltp/fsstress -x "echo 3 > /proc/sys/vm/drop_caches && sleep 1" -X 10 -r -f fsync=3 -f write=8 -f dwrite=10 -f truncate=8 -f allocsp=0 -f bulkstat=0 -f bulkstat1=0 -f freesp=0 -f zero=0 -f collapse=0 -f insert=0 -f resvsp=0 -f unresvsp=0 -S t -p 10 -n 10000 -d $TESTDIR/test
	umount $TESTDIR
	_mount
	;;
watch)
	_watch $2
	;;
all)
	_reload_f2fs
	cp local.config.enc local.config
	_check
	_fsstress
	;;
reset)
	_reset
	;;
esac
