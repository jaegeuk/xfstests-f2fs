#define _GNU_SOURCE
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <linux/types.h>
#include <sys/ioctl.h>
#include <unistd.h>

struct f2fs_move_range {
	__u32 dst_fd;		/* destination fd */
	__u64 pos_in;		/* start position in src_fd */
	__u64 pos_out;		/* start position in dst_fd */
	__u64 len;		/* size to move */
};

#define F2FS_IOCTL_MAGIC		0xf5
#define F2FS_IOC_MOVE_RANGE		_IOWR(F2FS_IOCTL_MAGIC, 9,	\
						struct f2fs_move_range)

int
main(int argc, char **argv)
{
	struct f2fs_move_range range;
	int fd_in, fd_out;
	struct stat stat;
	loff_t len;
	int err;

	if (argc != 3) {
		fprintf(stderr, "Usage: %s <source> <destination>\n", argv[0]);
		exit(EXIT_FAILURE);
	}

	fd_in = open(argv[1], O_RDWR);
	if (fd_in == -1) {
		perror("open (argv[1])");
		exit(EXIT_FAILURE);
	}

	if (fstat(fd_in, &stat) == -1) {
		perror("fstat");
		exit(EXIT_FAILURE);
	}

	len = stat.st_size;

	fd_out = open(argv[2], O_CREAT | O_WRONLY | O_TRUNC, 0644);
	if (fd_out == -1) {
		perror("open (argv[2])");
		exit(EXIT_FAILURE);
	}

	range.dst_fd = fd_out;
	range.pos_in = 0;
	range.pos_out = 0;
	range.len = len;

	err = ioctl(fd_in, F2FS_IOC_MOVE_RANGE, &range);
	if (err) {
		perror("move_file_range");
		exit(EXIT_FAILURE);
	}

	close(fd_in);
	close(fd_out);
	exit(EXIT_SUCCESS);
}
