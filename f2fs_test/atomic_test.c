#if 0
#include <stdio.h>
#include <sys/syscall.h>
#include <string.h>
#include <fcntl.h>
#include <getopt.h>
#include <errno.h>
#include <sys/ioctl.h>
#include <unistd.h>
#else
#include <sys/syscall.h>
#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/time.h>
#include <unistd.h>
#endif

#define F2FS_IOCTL_MAGIC		0xf5
#define F2FS_IOC_START_ATOMIC_WRITE     _IO(F2FS_IOCTL_MAGIC, 1)
#define F2FS_IOC_COMMIT_ATOMIC_WRITE    _IO(F2FS_IOCTL_MAGIC, 2)
#define F2FS_IOC_START_VOLATILE_WRITE   _IO(F2FS_IOCTL_MAGIC, 3)
#define F2FS_IOC_RELEASE_VOLATILE_WRITE _IO(F2FS_IOCTL_MAGIC, 4)
#define F2FS_IOC_ABORT_VOLATILE_WRITE   _IO(F2FS_IOCTL_MAGIC, 5)
#define F2FS_IOC_GARBAGE_COLLECT        _IO(F2FS_IOCTL_MAGIC, 6)

#define DB1_PATH "/mnt/test/database_file1"
#define DB2_PATH "/mnt/test/database_file2"
#define JOURNAL_PATH "/mnt/test/journal_file"

#define BLOCK 4096
#define BLOCKS (2*BLOCK)
int buf[BLOCKS];
char cmd[BLOCK];

void main(int argc, char **argv)
{
	int db1, db2, jd;
	int ret;
	int written;
	int i;

	memset(buf, 0xff, BLOCKS);

	printf("Opening db file ... \n");
	db1 = open(DB1_PATH, O_RDWR|O_CREAT);
	if (db1 < 0) {
		printf("open failed errno:%d\n", errno);
		return;
	}

	printf("Opening db2 file ... \n");
	db2 = open(DB2_PATH, O_RDWR|O_CREAT);
	if (db2 < 0) {
		printf("open failed errno:%d\n", errno);
		return;
	}

	printf("Opening journal file ... \n");
	jd = open(JOURNAL_PATH, O_RDWR|O_CREAT);
	if (jd < 0) {
		printf("open failed errno:%d\n", errno);
		return;
	}

	printf("1: SINGLE ATOMIC WRITE\n");
	ret = ioctl(db1, F2FS_IOC_START_ATOMIC_WRITE);
	if (ret) {
		printf("ioctl failed errno:%d\n", errno);
		return;
	}

	printf("Write to the %dkB ... \n", BLOCKS / 1024);
	written = write(db1, buf, BLOCKS);
	if (written != BLOCKS) {
		printf("write fail written:%d, errno:%d\n", written, errno);
		return;
	}

	printf("Commit  ... \n");
	ret = ioctl(db1, F2FS_IOC_COMMIT_ATOMIC_WRITE);
	if (ret) {
		printf("ioctl failed errno:%d\n", errno);
		return;
	}

	printf("Check : Atomic write count: 0 (Max. 1)\n");
	getchar();

	printf("2: TWO CONCURRENT ATOMIC WRITES\n");
	ret = ioctl(db1, F2FS_IOC_START_ATOMIC_WRITE);
	if (ret) {
		printf("ioctl failed errno:%d\n", errno);
		return;
	}
	ret = ioctl(db2, F2FS_IOC_START_ATOMIC_WRITE);
	if (ret) {
		printf("ioctl failed errno:%d\n", errno);
		return;
	}

	printf("Write to the 4kB to DB1 ... \n");
	written = write(db1, buf, BLOCK);
	if (written != BLOCK) {
		printf("write fail written:%d, errno:%d\n", written, errno);
		return;
	}
	printf("Write to the 4kB to DB2 ... \n");
	written = write(db2, buf, BLOCK);
	if (written != BLOCK) {
		printf("write fail written:%d, errno:%d\n", written, errno);
		return;
	}
	printf("Write to the 4kB to DB1 ... \n");
	written = write(db1, buf, BLOCK);
	if (written != BLOCK) {
		printf("write fail written:%d, errno:%d\n", written, errno);
		return;
	}

	printf("Check : Atomic write count: 2 (Max. 2)\n");
	printf("Check : inmem_pages == 3  ... \n");
	getchar();

	printf("Commit DB1 ... \n");
	ret = ioctl(db1, F2FS_IOC_COMMIT_ATOMIC_WRITE);
	if (ret) {
		printf("ioctl failed errno:%d\n", errno);
		return;
	}
	printf("Write to the 4kB to DB2 ... \n");
	written = write(db2, buf, BLOCK);
	if (written != BLOCK) {
		printf("write fail written:%d, errno:%d\n", written, errno);
		return;
	}

	printf("Check : Atomic write count: 1 (Max. 2)\n");
	printf("Check : inmem_pages == 2  ... \n");
	getchar();

	printf("Commit DB2 ... \n");
	ret = ioctl(db2, F2FS_IOC_COMMIT_ATOMIC_WRITE);
	if (ret) {
		printf("ioctl failed errno:%d\n", errno);
		return;
	}

	printf("Check : Atomic write count: 0 (Max. 2)\n");
	printf("Check : inmem_pages == 0  ... \n");
	getchar();

	printf("3: SINGLE VOLATILE WRITE\n");
	ret = ioctl(jd, F2FS_IOC_START_VOLATILE_WRITE);
	if (ret) {
		printf("ioctl failed errno:%d\n", errno);
		return;
	}

	printf("Write to the first page ... \n");
	written = write(jd, buf, BLOCK);
	if (written != BLOCK) {
		printf("write fail written:%d, errno:%d\n", written, errno);
		return;
	}
	getchar();

	printf("Release the volatile file ... \n");
	ret = ioctl(jd, F2FS_IOC_RELEASE_VOLATILE_WRITE);
	if (ret) {
		printf("ioctl failed errno:%d\n", errno);
		return;
	}

	printf("Ending before close\n");
	sprintf(cmd, "hexdump %s", JOURNAL_PATH);
	system(cmd);
	getchar();

	close(db1);
	close(db2);
	close(jd);
}
