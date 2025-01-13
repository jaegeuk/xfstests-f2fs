#!/bin/bash

VER=f2fs
DEV=vdb
MAIN=vdc
MAINDEV=vdd
TESTDIR=/mnt/test

pids=`pidof sshd`
for i in $pids
do
	echo -17 > /proc/$i/oom_adj
done
echo -17 > /proc/`cat /var/run/sshd.pid`/oom_adj

truncate --size 0 /var/log/kern.log

_reload()
{
	umount /mnt/*
	rmmod f2fs
	insmod ~/$VER/fs/f2fs/f2fs.ko
	modprobe dm-thin-pool
}

_mkfs()
{
	case $1 in
	"f2fs")
		mkfs.f2fs -f -O extra_attr -O project_quota -O compression -g android /dev/$DEV;;
	esac
}

__unlock_crypt()
{
	kernel=`uname -r`
	version=`echo ${kernel%.*}`
	if [ "$version" != "4.14" ] && [ "$version" != "4.19" ]; then
		fscrypt unlock --user=root $TESTDIR/crypt_test << EOF
password
EOF
	fi
}

_mount()
{
	case $1 in
	"f2fs")
		mount -t f2fs -o discard,fsync_mode=nobarrier,reserve_root=32768,checkpoint_merge,atgc,compress_cache /dev/$DEV $TESTDIR
		f2fs=`mount | grep $TESTDIR | grep f2fs`
		if [ ! "$f2fs" ]; then
			exit
		fi
		_fs_opts
		;;
	"f2fs_comp")
		mount -t f2fs -o discard,compress_extension=* /dev/$DEV $TESTDIR
		;;
	*)
		mount -t $1 -o discard /dev/$DEV $TESTDIR
		;;
	esac
	__unlock_crypt
}

_umount()
{
	echo "Unmount"
	umount $TESTDIR
	if [ $? -ne 0 ]; then
		for i in `seq 1 50`
		do
			umount $TESTDIR
			if [ $? -eq 0 ]; then
				break
			fi
			sleep 5
		done
	fi
}

_fsck()
{
	rand=`shuf -i 3000-500000 -n 1`
	fsck.f2fs -a -c $rand --debug-cache /dev/$DEV
	res=`fsck.f2fs --dry-run /dev/$DEV | grep "Fail" | sed '/other corrupted/d'`
	if [ "$res" ]; then
		echo $res
		exit
	fi
	fsck.f2fs -y -c $rand --debug-cache /dev/$DEV
}

_fsck_recovery()
{
	date
	echo "QUOTA may be failed"
	_fsck
	date
	echo "Mount for Recovery"
	_mount f2fs
	_umount
	date
	echo "QUOTA fix"
	_fsck
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
	echo 1 > /sys/fs/f2fs/$DEV/gc_urgent
	echo 0 > /sys/fs/f2fs/$DEV/atgc_age_threshold

	rand=`shuf -i 3000-5000 -n 1`
	echo $rand > /sys/fs/f2fs/$DEV/inject_rate
	echo 0xa7ff > /sys/fs/f2fs/$DEV/inject_type
}

_stop_fault()
{
	echo 0 > /sys/fs/f2fs/$DEV/inject_type
}

cur=0
_rm_50()
{
	_stop_fault
	for i in `seq 0 8`
	do
		idx=`printf '%x' $((($cur + $i)%16))`
		rm -rf "$TESTDIR/comp/p$idx" 2>/dev/null
		rm -rf "$TESTDIR/normal/p$idx" 2>/dev/null
		rm -rf "$TESTDIR/crypt_test/p$idx" 2>/dev/null
	done
	cur=$(($cur + 1))
	_fs_opts
}

__run_godown_fsstress()
{
	mkdir $TESTDIR/comp
	f2fs_io setflags compression $TESTDIR/comp
	ltp/fsstress -r -f drop=3 -f fsync=0 -f fdatasync=0 -f sync=0 -f write=4 -f dwrite=2 -f truncate=6 -f bulkstat=0 -f bulkstat1=0 -f zero=1 -f collapse=1 -f insert=1 -f resvsp=0 -f unresvsp=0 -S t -p 16 -n 200000 -d $TESTDIR/comp &
	ltp/fsstress -r -z -f drop=3 -f fsync=1 -f fdatasync=1 -f write=4 -f dwrite=0 -f truncate=1 -S t -p 16 -n 200000 -d $TESTDIR/normal &
	if [ "$version" != "4.14" ] && [ "$version" != "4.19" ]; then
		# dir
		ltp/fsstress -r -f drop=3 -f fsync=0 -f sync=0 -f write=0  -f read=0 -f dwrite=0 -f dread=0 -f bulkstat=0 -f bulkstat1=0 -f resvsp=0 -f unresvsp=0 -S t -p 16 -n 200000 -d $TESTDIR/crypt_test &
		# file
		ltp/fsstress -r -f drop=3 -f fsync=8 -f sync=0 -f write=4 -f dwrite=2 -f truncate=6 -f bulkstat=0 -f bulkstat1=0 -f zero=1 -f collapse=1 -f insert=1 -f resvsp=0 -f unresvsp=0 -S t -p 16 -n 200000 -d $TESTDIR/crypt_test &
		# whole
		ltp/fsstress -r -S t -p 16 -n 200000 -d $TESTDIR/crypt_test &
	fi
	sleep 240
	f2fs=`mount | grep $TESTDIR | grep f2fs`
	if [ "$f2fs" ]; then
		f2fs_io shutdown 2 $TESTDIR
	else
		killall fsstress
		pkill fsstress
		exit
	fi
	killall fsstress
	pkill fsstress
	sleep 5
}

__iter_por_fsstress()
{
	__run_godown_fsstress
	_umount
	echo 3 > /proc/sys/vm/drop_caches
	_fsck_recovery
	_mount f2fs
	_rm_50
}

por_fsstress()
{
	sudo systemctl mask snapd.service
	_fs_opts

	while true; do
		# w/ fault
		__iter_por_fsstress

		# w/o fault
		_stop_fault
		__iter_por_fsstress
	done
}

_set_crypt()
{
	kernel=`uname -r`
	version=`echo ${kernel%.*}`
	if [ "$version" == "4.14" ] || [ "$version" == "4.19" ]; then
		return
	fi
	fscrypt setup --force
	fscrypt setup --quiet $1
	mkdir $2
	fscrypt encrypt $2 --source=custom_passphrase --user=root --name="Super Secret" << EOF
password
password
EOF
}

_check()
{
	umount /mnt/*
#	t="$t tests/generic/126"
	if test -f ".xfstests.exclude"; then
		./check -x $1 -E .xfstests.exclude $t
	else
		./check -x $1 $t
	fi
}

case "$1" in
reload)
	_reload
	_mkfs f2fs
	_mount f2fs
	_set_crypt $TESTDIR $TESTDIR/crypt_test
	;;
xfstests)
	echo "Should turn CONFIG_KEYS_REQUEST_CACHE off!"
	cp local.config.noenc local.config
	_check "clone,dedupe,thin"
	;;
por_fsstress)
	por_fsstress
	;;
esac
