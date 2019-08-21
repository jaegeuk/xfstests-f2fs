#!/bin/bash

MAIN=/mnt/test
FILE=$MAIN/file
DIR=$MAIN/dir

_try()
{
	echo ""
	echo " == $1: $3 -> $4 =="
	rm -rf $1
	if [ "$2" == "file" ]; then
		touch $1
	else
		mkdir -p $1
	fi
	f2fs_io setflags $3 $1
	f2fs_io setflags $4 $1
}

_comp_stat()
{
	stat=`cat /sys/kernel/debug/f2fs/status | grep Compressed`
	inode=`echo $stat | awk '{print $4}' | sed -e 's/\,//'`
	blocks=`echo $stat | awk '{print $6}'`

	echo $inode / $blocks
	if [ "$inode" != "$1" ] || [ "$blocks" != "$2" ]; then
		echo "Check"
		exit
	fi
}

_comp_check()
{
	res=`f2fs_io getflags $1 | grep "flags=$2"`
	if [ ! "$res" ]; then
		echo "Check"
		exit
	fi
}

_try $FILE file nocompression compression
_comp_stat 0 0
_comp_check $FILE nocompression
_try $FILE file compression nocompression
_comp_stat 1 0
_comp_check $FILE compression
_try $DIR dir nocompression compression
_comp_stat 1 0
_comp_check $DIR nocompression
_try $DIR dir compression nocompression
_comp_stat 1 0
_comp_check $DIR compression

_read()
{
	echo ""
	echo " == Read $1'th block byte =="
	sync
	echo 3 > /proc/sys/vm/drop_caches
	start=$1
	for i in `seq 1 $2`
	do
		f2fs_io read 1 $start 1 buffered 4 $COMP_FILE
		start=$((start + 1))
	done
	sync
	echo 3 > /proc/sys/vm/drop_caches
	start=$1
	for i in `seq 1 $2`
	do
		f2fs_io read 1 $start 1 dio 4 $COMP_FILE
		start=$((start + 1))
	done
}

rm -rf $MAIN/*
sync
echo 3 > /proc/sys/vm/drop_caches
echo ""
echo " == Delete All =="
_comp_stat 0 0

echo ""
echo " == Inherit test =="
mkdir -p $MAIN/comp_dir
mkdir -p $MAIN/nocomp_dir
f2fs_io setflags compression $MAIN/comp_dir
touch $MAIN/comp_dir/comp_file
_comp_stat 1 0
f2fs_io setflags nocompression $MAIN/nocomp_dir
touch $MAIN/nocomp_dir/nocomp_file

_comp_stat 1 0
_comp_check $MAIN/comp_dir compression
_comp_check $MAIN/comp_dir/comp_file compression
_comp_check $MAIN/nocomp_dir nocompression
_comp_check $MAIN/nocomp_dir/nocomp_file nocompression

COMP_FILE=$MAIN/comp_dir/comp_file
echo ""
echo " == Write Once test =="
f2fs_io write 1 0 20 inc_num buffered $COMP_FILE
f2fs_io getflags $COMP_FILE
f2fs_io fiemap 0 20 $COMP_FILE
_read 0 4
_comp_stat 1 15

echo ""
echo " == Update 0'th block test =="
f2fs_io write 1 0 1 rand buffered $COMP_FILE
f2fs_io fiemap 0 20 $COMP_FILE
_read 0 4
_comp_stat 1 15

echo ""
echo " == Update 4'th block test =="
f2fs_io write 1 4 1 rand buffered $COMP_FILE
f2fs_io fiemap 0 20 $COMP_FILE
_read 3 5
_comp_stat 1 15

echo ""
echo " == Update 9'th block test =="
f2fs_io write 1 9 1 rand buffered $COMP_FILE
f2fs_io fiemap 0 20 $COMP_FILE
_read 8 4
_comp_stat 1 15

echo ""
echo " == Update 4x10'th block test =="
f2fs_io write 1 10 4 rand buffered $COMP_FILE
f2fs_io fiemap 0 20 $COMP_FILE
_read 8 4
_comp_stat 1 15

echo ""
echo " == Write Inline data test =="
rm $COMP_FILE
echo "inline small" > $COMP_FILE
f2fs_io getflags $COMP_FILE
f2fs_io fiemap 0 1 $COMP_FILE
xxd $COMP_FILE
_comp_stat 2 15
