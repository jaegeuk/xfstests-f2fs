#!/bin/sh

#VER=f2fs-3.18
#VER=f2fs-3.10
VER=f2fs
DEV=sdb1
TESTDIR=/mnt/test
PH_STORAGE=/var/lib/phoronix-test-suite

TESTSET="iozone fio fio fio fio tiobench tiobench dbench aio-stress fs-mark postmark compilebench unpack-linux"
AIO="aio-stress"
TIO="tiobench"
DBENCH="dbench"
SQLITE="sqlite"
MKFS="-t 1"

truncate --size 0 /var/log/kern.log

_reload()
{
	umount /mnt/*
	case $1 in
	f2fs)
		rmmod f2fs
		insmod ~/$VER/fs/f2fs/f2fs.ko
		;;
	xfs)
		rmmod xfs
		insmod ~/$VER/fs/xfs/xfs.ko
		;;
	esac
}

FS=f2fs

_check()
{
	umount /mnt/*
#	mkfs.$FS /dev/sdb1
#	mkfs.$FS /dev/sdc1
	mkfs.$FS -O encrypt $MKFS /dev/sdb1
	mkfs.$FS -O encrypt $MKFS /dev/sdc1
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

_mkfs()
{
	case $1 in
	"f2fs")
		mkfs.f2fs $MKFS -O encrypt /dev/$DEV;;
	"ext4")
		mkfs.ext4 -F /dev/$DEV;;
	"xfs")
		mkfs.xfs -f /dev/$DEV;;
	esac
}

_umount()
{
	umount /mnt/*
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
	case $1 in
	"f2fs")
		#mount -t f2fs /dev/$DEV -o no_heap,background_gc=off,active_logs=2,discard $TESTDIR
		#mount -t f2fs /dev/$DEV -o background_gc=sync,active_logs=6,discard $TESTDIR
		mount -t f2fs /dev/$DEV -o background_gc=on,active_logs=6,discard $TESTDIR
	#	mount -t f2fs /dev/$DEV -o background_gc=off,active_logs=6,discard $TESTDIR
		;;
	*)
		mount -t $1 -o discard /dev/$DEV $TESTDIR
		;;
	esac
}

_error()
{
	# CP blkaddr
	dd if=/dev/zero of=/dev/$DEV bs=4 seek=275 count=1
	_mount f2fs
	umount /mnt/*
}

_init()
{
	_umount
	_reload $1
	_mkfs $1
	_mount $1
	_fs_opts
}

_init_crypt()
{
	_umount
	_reload f2fs
	mkfs.f2fs $MKFS -O encrypt /dev/$DEV
	_error
	_mount f2fs
	mkdir $TESTDIR/test
	echo foo | e4crypt add_key -S 0x12 $TESTDIR/test
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
		_mount f2fs
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
		_mount f2fs
		rm -rf $TESTDIR/*
		umount $TESTDIR
		fsck.f2fs /dev/$DEV
		_mount f2fs
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

_fs_mark()
{
	time fs_mark  -D  10000  -S0  -n  100000  -s  0  -L  32	\
		-d  $TESTDIR/0  -d  $TESTDIR/1	\
		-d  $TESTDIR/2  -d  $TESTDIR/3 \
		-d  $TESTDIR/4  -d  $TESTDIR/5 \
		-d  $TESTDIR/6  -d  $TESTDIR/7 \
		-d  $TESTDIR/8  -d  $TESTDIR/9 \
		-d  $TESTDIR/10  -d  $TESTDIR/11 \
		-d  $TESTDIR/12  -d  $TESTDIR/13 \
		-d  $TESTDIR/14  -d  $TESTDIR/15 
	#	| tee >(stats --trim-outliers | tail -1 1>&2)
}

_ph()
{
	_umount
	_reload $1
	_mkfs $1
	_mount $1

	echo "git pull phoronix"
	echo "./phoronix-test-suite/install.sh"

	echo "mkdir /var/lib/phoronix-test-suite/download-cache/"
	echo "phoronix-test-suite make-download-cache"

	rm -rf $PH_STORAGE/installed-tests
	ln -s $TESTDIR $PH_STORAGE/installed-tests

	phoronix-test-suite info disk
	echo "phoronix-test-suite batch-setup"
	echo "phoronix-test-suite batch-benchmark pts/iozone pts/compress-7zip"
	echo "phoronix-test-suite merge-results 2012-12-30-2102 2012-12-30-2106"
	echo "phoronix-test-suite benchmark tiobench|compilebench|fs-mark|unpack-linux"
}

case "$1" in
reload)
	if [ $2 ]; then
		DEV=$2
	fi
	_reload f2fs
	#mkfs.f2fs -O encrypt /dev/$DEV
	#mkfs.f2fs -a 0 -s 20 /dev/$DEV
	mkfs.f2fs -t 0 -O encrypt /dev/$DEV
	#_error
	_mount f2fs
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
	_init f2fs
	_fsstress
	;;
por_fsstress)
	por_fsstress
	;;
test)
	umount /mnt/*
	mkfs.f2fs -O encrypt /dev/$DEV
	_mount f2fs
	mkdir $TESTDIR/test
	echo foo | e4crypt add_key -S 0x12 $TESTDIR
	_fs_opts
	ltp/fsstress -x "echo 3 > /proc/sys/vm/drop_caches && sleep 1" -X 10 -r -f fsync=3 -f write=8 -f dwrite=10 -f truncate=8 -f allocsp=0 -f bulkstat=0 -f bulkstat1=0 -f freesp=0 -f zero=0 -f collapse=0 -f insert=0 -f resvsp=0 -f unresvsp=0 -S t -p 10 -n 10000 -d $TESTDIR/test
	umount $TESTDIR
	_mount f2fs
	;;
watch)
	_watch $2
	;;
all)
	_reload f2fs
	cp local.config.enc local.config
	_check
	_fsstress
	;;
reset)
	_reset
	;;
aio)
	_ph f2fs
	export TEST_RESULTS_IDENTIFIER=F2FS
	phoronix-test-suite batch-benchmark $AIO
	;;
aio-xfs)
	_ph xfs
	export TEST_RESULTS_IDENTIFIER=F2FS
	phoronix-test-suite batch-benchmark $AIO
	;;
tio)
	_ph f2fs
	export TEST_RESULTS_IDENTIFIER=F2FS
	phoronix-test-suite batch-benchmark $TIO < tio_set
	;;
sqlite)
	_ph f2fs
	export TEST_RESULTS_IDENTIFIER=F2FS
	phoronix-test-suite batch-benchmark $SQLITE
	;;
dbench)
	_ph f2fs
	export TEST_RESULTS_IDENTIFIER=F2FS
	echo 4 | phoronix-test-suite batch-benchmark $DBENCH
	;;
tio-xfs)
	_ph xfs
	export TEST_RESULTS_IDENTIFIER=XFS
	phoronix-test-suite batch-benchmark $TIO < tio_set
	;;
phall)
	if [ $2 ]; then
		DEV=$2
	fi
	if [ $3 ]; then
		DESC=$3
	else
		DESC=$DEV
	fi
	_ph f2fs
	export TEST_RESULTS_IDENTIFIER=F2FS-$DESC
	phoronix-test-suite batch-benchmark $TESTSET < set
	_ph ext4
	export TEST_RESULTS_IDENTIFIER=EXT4-$DESC
	phoronix-test-suite batch-benchmark $TESTSET < set
	#_ph xfs
	#export TEST_RESULTS_IDENTIFIER=XFS-$DESC
	#phoronix-test-suite batch-benchmark $TESTSET < set
	ls /var/www/html/test-results/
	echo "phoronix-test-suite merge-results 2012-12-30-2102 2012-12-30-2106"
	;;
fs_mark)
	_init f2fs
	_fs_mark
	_init ext4
	_fs_mark
	;;
phall_two)
	./run.sh phall nvme0n1 NVME
	./run.sh phall sdb1 SSD
	;;
esac
