all:
	gcc -o server server.c rio.c sock_common.c sbuf.c -lpthread
	gcc -o client client.c rio.c sock_common.c
clean:
	rm -f server
	rm -f client
