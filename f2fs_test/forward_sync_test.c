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
#define F2FS_IOC_GARBAGE_COLLECT        _IO(F2FS_IOCTL_MAGIC, 6)
#define F2FS_IOC_CHECKPOINT		_IO(F2FS_IOCTL_MAGIC, 7)
#define F2FS_IOC_FORWARD_SYNC		_IO(F2FS_IOCTL_MAGIC, 10)

#define TESTFILE "/mnt/test/file1"

#define BLOCK 4096
#define BLOCKS 20000
int buf[BLOCK];
char cmd[BLOCK];
char name[1024];
#define NFILES 10

void main(int argc, char **argv)
{
	int fd[NFILES];
	int ret;
	int written;
	int i, j;

	memset(buf, 0xff, BLOCK);

	printf("Creating %d files ... \n", NFILES / 2);
	for (i = 0; i < NFILES / 2; i++) {
		sprintf(name, "%s%d", TESTFILE, i);
		fd[i] = open(name, O_RDWR|O_CREAT);
		if (fd[i] < 0) {
			printf("open failed errno:%d\n", errno);
			return;
		}
	}

	printf("Check : inode = %d, data has some dentry blocks\n", NFILES / 2);
	getchar();

	printf("Checkpoint ... \n");
	ret = ioctl(fd[0], F2FS_IOC_CHECKPOINT);
	if (ret) {
		printf("ioctl failed errno:%d\n", errno);
		return;
	}

	printf("Check : no dents, nodes\n");
	getchar();

	printf("Write to the %d files having %dMB ... \n",
				NFILES / 2, BLOCK*BLOCKS/1024/1024);
	for (j = 0; j < NFILES / 2; j++) {
		for (i = 0; i < BLOCKS; i++) {
			written = write(fd[j], buf, BLOCK);
			if (written != BLOCK) {
				printf("write fail written:%d, errno:%d\n",
							written, errno);
				return;
			}
		}
	}

	printf("Creating another %d files ... \n", NFILES / 2);
	for (i = NFILES / 2; i < NFILES; i++) {
		sprintf(name, "%s++%d", TESTFILE, i);
		fd[i] = open(name, O_RDWR|O_CREAT);
		if (fd[i] < 0) {
			printf("open failed errno:%d\n", errno);
			return;
		}
	}

	printf("Check : many data and node blocks\n");
	getchar();
	
	printf("FORWARD SYNC ... \n");
	ret = ioctl(fd[0], F2FS_IOC_FORWARD_SYNC);
	if (ret) {
		printf("ioctl failed errno:%d\n", errno);
		return;
	}

	printf("Check : no data and node block, but some dentry blocks\n");
	getchar();

	for (i = 0; i < NFILES; i++)
		close(fd[i]);
}
