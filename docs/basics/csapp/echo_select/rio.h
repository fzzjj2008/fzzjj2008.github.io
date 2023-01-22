#ifndef _RIO_H_
#define _RIO_H_

#include <unistd.h>
#include <stddef.h>
#define RIO_BUFSIZE 8192

typedef struct {
    int rio_fd;                //与内部缓冲区关联的描述符
    int rio_cnt;               //缓冲区中剩下的字节数
    char *rio_bufptr;          //指向缓冲区中下一个未读的字节
    char rio_buf[RIO_BUFSIZE]; 
} rio_t;

ssize_t rio_readn(int fd, void *usrbuf, size_t n);
ssize_t rio_writen(int fd, void *usrbuf, size_t n);
void rio_readinitb(rio_t *rp, int fd);
ssize_t rio_readnb(rio_t *rp, void *usrbuf, size_t n);
ssize_t rio_readlineb(rio_t *rp, void *usrbuf, size_t maxlen);

#endif /* _RIO_H_ */

