#include <stdio.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

int main(int argc, char *argv[])
{
	char buf[4096];
	int fd;
	int large_size = 1024 * 1024 * 700; /* 700 MB */

	memset(buf, 0xff, 4096);

	fd = open(argv[1], O_RDWR | O_CREAT, 0777);
	if (fd < 0) {
		perror("open");
		return fd;
	}
	lseek(fd, 4096, SEEK_SET);
	if (write(fd, &buf, large_size) < 0)
		perror("write");
	close(fd);
	return 0;
}
