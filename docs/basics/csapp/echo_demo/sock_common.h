#ifndef _SOCK_COMMON_
#define _SOCK_COMMON_

typedef struct sockaddr SA;

int open_clientfd(char *hostname, char *port);
int open_listenfd(char *port);

#endif /* _SOCK_COMMON_ */
