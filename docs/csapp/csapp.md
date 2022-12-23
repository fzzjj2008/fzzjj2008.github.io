## 7.1 概述

- **链接（linking）**：将代码和数据片段合并成一个单一文件的过程，由**链接器（linker）**自动完成
- **静态链接器(static linker)**：如LD，可以将一组**可重定位目标文件**和命令行为输入，生成可执行二进制文件
- **链接器的主要任务**：符号解析、重定位
  - 符号解析：将每个符号引用与符号定义关联
  - 重定位：将符号定义与内存位置关联，从而重定位这些节。然后修改所有符号引用，使他们指向这个内存位置

【例】书中例子，`sum.c`和`main.c`，使用链接器生成二进制文件

```C++
// sum.c
int sum(int *a, int n) {
    int i, s = 0;
    for (i = 0; i < n ; i++) {
        s += a[i];
    }
    return s;
}

// main.c
int sum(int *a, int n);

int array[2] = {1, 2};

int main() {
    int val = sum(array, 2);
    return val;
}
```

【链接】`gcc -Og -o prog main.c sum.c`（加-v选项可以看到全过程）

【说明】生成二进制文件的过程实际分为三步：编译+汇编+链接

```shell
# 预处理，生成main.i
cpp -o main.i main.c    #或执行gcc -E -o main.i main.c
# 编译
cc -S -o main.s main.i  #或执行gcc -S -o main.s main.i
# 汇编，生成可重定位目标文件main.o
as -o main.o main.s
# 链接
ld -o prog main.o sum.o -dynamic-linker \
    /lib64/ld-linux-x86-64.so.2         \
    /usr/lib/x86_64-linux-gnu/crt1.o    \
    /usr/lib/x86_64-linux-gnu/crti.o    \
    /usr/lib/x86_64-linux-gnu/libc.so   \
    /usr/lib/x86_64-linux-gnu/crtn.o
# 执行，加载器将程序加载到内存中执行
./prog
```



## 7.4 可重定位目标文件

- **可重定位目标文件（relocatable object files）**：由代码和数据节（section）组成，每一节都是一个连续的字节序列
- **ELF格式**：Linux和Unix系统使用可执行可链接格式（Executable and Linkable Format, ELF）
  - **ELF header**：64字节，包含魔数、ELF文件类型、字节序、版本号、ELF头大小、目标文件类型、机器类型、节头部表的偏移、节头部表中条目的大小和数量
  - **sections**
    - .text：已编译程序的机器代码（反汇编：`objdump -s -d main.o`）
    - .rodata：只读数据，如printf的字符串和switch语句的跳转表
    - .data：已初始化的全局变量和静态变量（局部变量位于栈中）
    - .bss：未初始化的全局变量和静态变量，以及初始化为0的全局变量和静态变量（不占空间，只有1个占位符）
    - .symtab：符号表，定义引用函数和全局变量信息（注意：没有gcc -g也会有.symtab）
    - .debug：调试用符号表，gcc -g选项开启后才有这张表
    - ...
  - **section header table**：描述节属性的表

![image-20221222075831485](C:\Users\THINKPAD\Desktop\learning\csapp\image-20221222075831485.png)

```shell
# #查看ELF header
# readelf -h main.o
ELF Header:
  Magic:   7f 45 4c 46 02 01 01 00 00 00 00 00 00 00 00 00
  Class:                             ELF64
  Data:                              2's complement, little endian
  Version:                           1 (current)
  OS/ABI:                            UNIX - System V
  ABI Version:                       0
  Type:                              REL (Relocatable file)
  Machine:                           Advanced Micro Devices X86-64
  Version:                           0x1
  Entry point address:               0x0
  Start of program headers:          0 (bytes into file)
  Start of section headers:          304 (bytes into file)
  Flags:                             0x0
  Size of this header:               64 (bytes)
  Size of program headers:           0 (bytes)
  Number of program headers:         0
  Size of section headers:           64 (bytes)
  Number of section headers:         12
  Section header string table index: 9
  
# #查看ELF sections
# readelf -S main.o
There are 12 section headers, starting at offset 0x130:

Section Headers:
  [Nr] Name              Type             Address           Offset
       Size              EntSize          Flags  Link  Info  Align
  [ 0]                   NULL             0000000000000000  00000000
       0000000000000000  0000000000000000           0     0     0
  [ 1] .text             PROGBITS         0000000000000000  00000040
       000000000000001f  0000000000000000  AX       0     0     1
  [ 2] .rela.text        RELA             0000000000000000  00000550
       0000000000000030  0000000000000018          10     1     8
  [ 3] .data             PROGBITS         0000000000000000  00000060
       0000000000000008  0000000000000000  WA       0     0     4
  [ 4] .bss              NOBITS           0000000000000000  00000068
       0000000000000000  0000000000000000  WA       0     0     1
  [ 5] .comment          PROGBITS         0000000000000000  00000068
       000000000000002c  0000000000000001  MS       0     0     1
  [ 6] .note.GNU-stack   PROGBITS         0000000000000000  00000094
       0000000000000000  0000000000000000           0     0     1
  [ 7] .eh_frame         PROGBITS         0000000000000000  00000098
       0000000000000038  0000000000000000   A       0     0     8
  [ 8] .rela.eh_frame    RELA             0000000000000000  00000580
       0000000000000018  0000000000000018          10     7     8
  [ 9] .shstrtab         STRTAB           0000000000000000  000000d0
       0000000000000059  0000000000000000           0     0     1
  [10] .symtab           SYMTAB           0000000000000000  00000430
       0000000000000108  0000000000000018          11     8     8
  [11] .strtab           STRTAB           0000000000000000  00000538
       0000000000000017  0000000000000000           0     0     1
  
# #反汇编
# objdump -s -d main.o

main.o:     file format elf64-x86-64

Contents of section .text:
 0000 554889e5 4883ec10 be020000 00bf0000  UH..H...........
 0010 0000e800 00000089 45fc8b45 fcc9c3    ........E..E...
Contents of section .data:
 0000 01000000 02000000                    ........
Contents of section .comment:
 0000 00474343 3a202855 62756e74 7520342e  .GCC: (Ubuntu 4.
 0010 382e342d 32756275 6e747531 7e31342e  8.4-2ubuntu1~14.
 0020 30342e34 2920342e 382e3400           04.4) 4.8.4.
Contents of section .eh_frame:
 0000 14000000 00000000 017a5200 01781001  .........zR..x..
 0010 1b0c0708 90010000 1c000000 1c000000  ................
 0020 00000000 1f000000 00410e10 8602430d  .........A....C.
 0030 065a0c07 08000000                    .Z......

Disassembly of section .text:

0000000000000000 <main>:
   0:   55                      push   %rbp
   1:   48 89 e5                mov    %rsp,%rbp
   4:   48 83 ec 10             sub    $0x10,%rsp
   8:   be 02 00 00 00          mov    $0x2,%esi
   d:   bf 00 00 00 00          mov    $0x0,%edi
  12:   e8 00 00 00 00          callq  17 <main+0x17>
  17:   89 45 fc                mov    %eax,-0x4(%rbp)
  1a:   8b 45 fc                mov    -0x4(%rbp),%eax
  1d:   c9                      leaveq
  1e:   c3                      retq
```

