#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define MAXLINE 1024

int main() {
    char *buf, *p;
    char arg1[MAXLINE], arg2[MAXLINE], content[MAXLINE];
    int n1 = 0, n2 = 0;

    /* Extract the two arguments */
    if ((buf = getenv("QUERY_STRING")) != NULL) {
        p = strchr(buf, '&');
        *p = '\0';
        sscanf(buf, "num1=%d", &n1);
        sscanf(p+1, "num2=%d", &n2);
    }
    /* Make the response body */
    sprintf(content, "THE Internet addition portal.\r\n<p>");
    sprintf(content+strlen(content), "The answer is: %d + %d = %d\r\n<p>",
            n1, n2, n1 + n2);
    sprintf(content+strlen(content), "Thanks for visiting!\r\n");

    /* Generate the HTTP response */
    printf("Connection: close\r\n");
    printf("Content-length: %d\r\n", (int)strlen(content));
    printf("Content-type: text/html\r\n\r\n");
    printf("%s", content);
    fflush(stdout);

    exit(0);
}

