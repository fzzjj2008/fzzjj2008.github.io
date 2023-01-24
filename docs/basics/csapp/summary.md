# 总结

点击[这里](https://github.com/fzzjj2008/fzzjj2008.github.io/tree/main/docs/basics/csapp/csapp.xmind)下载

```mindmap
CSAPP
  ch02 信息的表示和处理
    信息存储
      最小寻址单位：字节
      寻址方式：小端法、大端法
      字节运算：位运算（&、|、~、^）；逻辑运算（&&、||、!）；移位运算（逻辑移位、算数移位）
    整数表示
      编码：无符号数、有符号数（补码）
      扩展、溢出和截断
      加法、乘法、2的幂运算
    浮点数表示
      IEEE浮点数表示（规格化、非规格化、特殊值）
      舍入（向偶数舍入、向零舍入、向下舍入、向上舍入）
      运算：注意溢出，不具备加法结合律、乘法结合律、乘法分配律
  ch03 程序的机器级表示
    编码过程：源代码->汇编代码->可执行文件
    汇编指令：操作码+操作数
      操作数
        立即数、寄存器、内存引用
      操作码
        信息访问
          movq、pushq/popq
        算数和逻辑操作
          leaq、incq/subq、移位(salq/sarq/shlq/shrq)、mulq
        控制
          cmp、test、jmp、条件跳转(如jz)、条件传送(cmov)
        循环
          条件测试和跳转指令
    函数调用
      栈、栈帧、参数传递、局部变量、递归
      操作码
        call、ret
    数组和指针
      一维数组、多维数组、变长数组
    结构体和联合
      结构体表示、字节对齐
    异常
      内存越界、缓冲区溢出
    浮点表示
      media寄存器集
        AVX2
      浮点运算
        与整数指令类似，会更加复杂，支持并行操作
  ch04 处理器体系结构
    Y86-64指令集体系
      寄存器、条件码、程序计数器、内存、状态码
    Y86-64顺序实现
      取指、译码、执行、访存、写回、更新PC
    Y86-64流水线实现
      数据冒险、控制冒险
      分支预测
      暂停和气泡处理
  ch05 优化程序性能
    选择适当的算法和数据结构
    消除连续的函数调用、消除不必要的内存引用
    低级优化
      循环展开
      运算重新结合
      SIMD并行计算
      编译器能够优化的代码
  ch06 存储器层次结构
    存储技术
      主存
        物理结构：RAM、ROM
        访问原理：CPU(地址)->系统总线->IO桥->内存总线->主存(DRAM)取数据字
      机械硬盘
        物理结构：盘片、柱面、磁道、扇区、数据位
        访问时间：寻道时间+旋转时间+传送时间
        访问原理：CPU(逻辑块号、内存地址)->磁盘控制器->DMA传送->中断->CPU
    局部性原理
      空间局部性
        内存附近位置将被引用
      时间局部性
        内存将被多次引用
    高速缓存
      概念：缓存命中/不命中、替换算法(LRU)
      物理结构：cache line、block、valid bit、tag bit
      映射方式：直接映射、组相联、全相联
        组选择、行匹配、字选择
      读缓存过程、写缓存过程
  ch07 链接
    链接：将代码和数据片段合并成单一文件
    ELF文件
      结构
        ELF header
          readelf -h main.o
        sections
          .text、.data、.rodata、.bss、.symtab、.rel.text/.rel.data、.line、.debug
          objdump -s -d main.o
        section header table
          readelf -S main.o
      分类
        可重定位目标文件
          main.o
        可执行目标文件
          二进制可执行文件
        共享目标文件
          静态库或动态库
    链接过程
      可重定位目标文件
      符号解析
        作用：每个符号分配运行时地址
        同名符号解析
          强符号优先
      重定位
        相同的节合并
        修改符号引用地址
          相对地址重定位、绝对地址重定位
    加载过程
      可执行目标文件
        代码段（只读）、数据段（读/写）、符号表和调试信息
        新增程序入口点（.init），不存在重定位段（.rel.text/.rel.data）
      加载过程
        加载器复制代码段和数据段到内存->跳转程序入口_start->调用__libc_start_main->调用main函数->处理返回值，控制返回内核
    静态链接
      静态库libxxx.a
        静态库代码复制到每个运行进程中
      优缺点
        运行时内存浪费，更新库需重编译
    动态链接
      动态库libxxx.so
        重定位动态库的代码段和数据段的符号引用
      优缺点
        程序共享动态库单一副本，更新库无需重编译
  ch08 异常控制流
    异常
      中断、陷阱、故障、终止
      系统调用
        应用程序通过一些函数访问系统的资源
        参数传递、调用过程
    进程
      基本概念：进程、上下文、并发、并行、特权级
      上下文切换
        进程调度、系统调用、中断
      进程控制
        运行状态：运行、停止、终止
        创建（fork）、销毁（exit）、回收（wait/waitpid）、加载新程序（execve）
    信号
      发送信号
      接收信号
      阻塞和解除信号
      信号的安全使用
  ch09 虚拟内存
    概念：物理地址、虚拟地址、寻址、地址空间
    虚拟页
      概念：页、页帧、页表、页命中、缺页、页面调度、MMU、TLB
      地址翻译
        通过TLB或MMU获取页号，得到物理地址
        从高速缓存或内存取出数据
      页命中操作
        CPU查询虚拟地址->查询PTE->MMU找到物理地址->CPU查询物理地址数据（结合高速缓存）
      缺页操作
        CPU执行指令->查询PTE->缺页中断->调度页面->更新PTE->再次执行缺页指令
    Linux虚拟内存系统
      用户空间（独享）
        代码、数据、堆、共享库、栈段
      内核空间（共享）
        内核代码和数据、进程相关数据结构（页表、内核栈等）
        虚拟内存组织：task_struct、mm_struct、vm_area_struct
    内存映射(mmap)
      文件映射、匿名映射、共享映射、私有映射
      写时复制
        创只读副本，使用缺页操作恢复可写
    动态内存分配(malloc)
      brk指针、sbrk()
      碎片管理
        块组织：合理分配、合并块
      分配器的实现
        伙伴系统
  ch10 系统级I/O
    文件
      概念：文件、描述符
      分类：普通文件、目录、套接字、管道、设备等
      文件操作
        read、write、open、close、stat、readdir、dup2
      文件数据结构
        描述符表、文件表、v-node表
  ch11 网络编程
    通用模型：服务端-客户端
    概念：IP地址、域名、OSI模型
    套接字
      服务端
        socket、bind、listen、accept、read/write、close
      客户端
        socket、connect、read/write、close
    web服务器
      概念：HTTP、MIME类型、HTML、URL、URI
      HTTP请求
        请求方法：GET、POST、PUT、DELETE等
        格式：请求行、请求报头、请求主体
      HTTP响应
        格式：响应行、响应报头、响应主体
        状态码
          2XX、3XX、4XX、5XX
      动态内容
        CGI程序
  ch12 并发编程
    基于进程
      请求到达后，派生子进程处理
    基于IO多路复用
      IO多路复用(select/poll/epoll)、事件驱动
    基于线程
      线程模型
        共享进程虚拟地址空间、打开文件集合
      同步错误和信号量
      线程安全、可重入性和死锁
```
