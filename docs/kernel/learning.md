## 3.1 概述
- 虚拟地址空间：每个进程各自有自己的逻辑地址空间。在IA-32系统上，进程寻址范围是0 ~ 4GB。地址空间被典型划分为3GB的用户空间和1GB的内核空间

![image-20220831062604088](C:\Users\THINKPAD\Desktop\learning\learning\image-20220831062604088.png)

- 管理物理内存方式：
  - `UMA`（一致内存访问, `uniform memory access`）：将可用内存以连续方式组织起来。SMP系统每个处理器访问个内存区都一样快（结构对称）
  - `NUMA`（非一致内存访问, non-uniform memory access）：仅用于多处理器计算机，各个CPU有各自的本地内存。CPU可以访问其它CPU的内存，但是比访问本地内存慢（结构非对称）
  【注】书中重点考虑`UMA`系统的平坦内存模型`FLATMEM`，不考虑`CONFIG_NUMA`宏

![image-20220831062648255](C:\Users\THINKPAD\Desktop\learning\learning\image-20220831062648255.png)

```bash
# numactl -H
available: 2 nodes (0-1)
node 0 cpus: 0 1 2 3 4 5 6 7 8 9 10 11 12 13 28 29 30 31 32 33 34 35 36 37 38 39 40 41
node 0 size: 79946 MB
node 0 free: 14940 MB
node 1 cpus: 14 15 16 17 18 19 20 21 22 23 24 25 26 27 42 43 44 45 46 47 48 49 50 51 52 53 54 55
node 1 size: 80597 MB
node 1 free: 55633 MB
node distances:
node   0   1
  0:  10  21
  1:  21  10
```




## 3.2 (N)UMA模型中的内存组织
### 3.2.1 术语定义
- **结点**：内核将物理内存划分为结点，每个结点关联到系统的一个处理器。内核中有`pg_data_t`的实例。
	- NUMA系统：各个内存结点保存在一个单链表中，供内核遍历。内核按照结点距离远近，**优先遍历当前运行CPU相关联的结点**
	  - 每个结点都提供了一个备用列表`struct zonelist`，列表项越靠后越不适合分配
	- UMA系统：NUMA系统的特例，只有一个结点（图3-3的内存结点减少为一个），其余不变

![image-20220912120110013](C:\Users\THINKPAD\Desktop\learning\learning\image-20220912120110013.png)

- **内存域**：IA-32系统上，虚拟地址空间的3G ~ 4G属于内核空间，其中3G ~ 3G+896M直接映射物理地址的0~896M
  - Linux把每个内存结点的物理内存划分为3个管理区`zone_type`：
  	- ZONE_DMA：0~16M，专门供I/O设备的DMA使用
  	- ZONE_NORMAL：16~896M，内核可以直接使用该区域的物理页面
  	- ZONE_HIGHMEM：896~1024M，属于高端内存，由于线性地址空间不足物理页面需要动态映射，所以不能由内核直接访问（64位系统地址空间充足，取消此区域）
  - 各个内存域关联一个数组，组织物理内存页（即页帧）。对每个页帧，内核分配一个`struct page`实例及所需的管理数据

```C++
enum zone_type {
#ifdef CONFIG_ZONE_DMA
    ZONE_DMA,                   //DMA设备使用，32位计算机该区域为16MB
#endif
#ifdef CONFIG_ZONE_DMA32
    ZONE_DMA32,                 //32位计算机该区域为空，64位系统上两种DMA才有区别
#endif
    ZONE_NORMAL,                //普通内存域，所有体系上都存在，
#ifdef CONFIG_HIGHMEM
    ZONE_HIGHMEM,               //高端内存
#endif
    ZONE_MOVABLE,               //伪内存域，防止物理内存碎片的机制用到，见3.5.2节
    MAX_NR_ZONES
};
```

### 3.2.2 数据结构

**1. 结点管理**：`pg_data_t`定义了内存结点的基本元素，包括：内存域、页帧、结点编号、交换守护进程等

```C++
typedef struct pglist_data {
    struct zone node_zones[MAX_NR_ZONES];          //结点中各内存域的数据结构
    struct zonelist node_zonelists[MAX_ZONELISTS]; //备用列表，当前结点没有可用空间时，在备用结点分配内存
    int nr_zones;                                  //内存域数目
#ifdef CONFIG_FLAT_NODE_MEM_MAP
    struct page *node_mem_map;                     //指向结点的所有物理内存页（页帧）
#endif
    struct bootmem_data *bdata;                    //用于内存管理子系统初始化的自举，自举内存分配器数据结构的实例
......
    unsigned long node_start_pfn;                  //NUMA结点第一个页帧的逻辑编号，编号全局唯一。UMA中总是0
    unsigned long node_present_pages;              //结点中页帧总数
    unsigned long node_spanned_pages;              //结点含多少个页帧（中间可能有空洞，空洞不对应真正的页帧）
    int node_id;                                   //全局结点ID，从0开始编号
    wait_queue_head_t kswapd_wait;                 //交换守护进程的等待队列
    struct task_struct *kswapd;                    //交换守护进程的task_struct
    int kswapd_max_order;                          //用于页交换子系统的实现，定义需要释放区域的长度
} pg_data_t;
```

- **结点状态管理**：内核维护位图，记录各个结点的状态信息：结点是否有普通内存域、是否有高段内存域等等
  - 在`/sys/devices/system/node/`可以看到节点的详细信息
  - 使用`node_set_state()`和`node_clear_state()`设置或清除比特位


```C++
enum node_states {
    N_POSSIBLE,            /* 结点在某个时刻可能变为online */
    N_ONLINE,            /* 结点是online的 */
    N_NORMAL_MEMORY,    /* 节点有普通内存域，没有高端内存域 */
#ifdef CONFIG_HIGHMEM
    N_HIGH_MEMORY,        /* 节点有普通或高端内存域 */
#else
    N_HIGH_MEMORY = N_NORMAL_MEMORY,
#endif
    N_CPU,                /* 节点有一个或多个CPU */
    NR_NODE_STATES
};
```

**2. 内存域**：内核使用`struct zone`描述内存域

- 由`ZONE_PADDING`分隔为几个部分：这个结构体访问非常频繁。为了提高执行的性能，将两个自旋锁`zone->lock`和`zone->lru_lock`对齐到不同cache line中
- 包含几个部分：页分配器访问的字段、页面收回扫描程序访问的字段、很少使用或大多数情况只读的字段

```C++
struct zone {
    //影响页交换的行为：内存不足则换到硬盘上
    //空闲页多于pages_high，内存域状况理想
    //空闲页低于pages_low，页换出到硬盘；
    //空闲页低于pages_min，页回收压力大，即内存域急需空闲页。
    unsigned long        pages_min, pages_low, pages_high;
    //为各个内存域预留若干页，用于无论如何不能失败的关键性内存分配
    unsigned long        lowmem_reserve[MAX_NR_ZONES];
    //用于实现每个CPU的热页列表和冷页列表
    struct per_cpu_pageset    pageset[NR_CPUS];
    spinlock_t        lock;                         //自旋锁
    struct free_area    free_area[MAX_ORDER];     //用于实现伙伴系统，3.5.5节

    ZONE_PADDING(_pad1_)
    spinlock_t        lru_lock;    
    struct list_head    active_list;       //活动页的集合
    struct list_head    inactive_list;     //不活动页的集合
    unsigned long        nr_scan_active;    //指定在回收内存时，需要扫描的活动页的数目
    unsigned long        nr_scan_inactive;  //指定在回收内存时，需要扫描的不活动页的数目
    unsigned long        pages_scanned;       //上次换出一页以来，有多少页未能成功扫描
    //内存域当前状态，允许使用以下标志
    //ZONE_ALL_UNRECLAIMABLE：内存试图页面回收，但是所有的页都已经“钉”住而无法回收（如mlock系统调用）
    //ZONE_RECLAIM_LOCKED：防止多个CPU并发回收
    //ZONE_OOM_LOCKED：进程OOM消耗大量内存，内核杀死该进程，此时要防止多个CPU同时回收内存
    unsigned long        flags;
    //维护有关该内存域的统计信息，见17.7.1节。用zone_page_state读取信息
    atomic_long_t        vm_stat[NR_VM_ZONE_STAT_ITEMS];
    //存储了上一次扫描操作扫描该内存域的优先级
    int prev_priority;

    ZONE_PADDING(_pad2_)
    //以下3个字段实现了一个等待队列，等待某一页变为可用的进程使用
    wait_queue_head_t    * wait_table;
    unsigned long        wait_table_hash_nr_entries;
    unsigned long        wait_table_bits;
    //建立内存域和父结点的关联
    struct pglist_data    *zone_pgdat;
    /* zone_start_pfn == zone_start_paddr >> PAGE_SHIFT */
    unsigned long        zone_start_pfn; //内存域第一个页帧的索引
    unsigned long        spanned_pages;    //较少使用，内存域中页的总数，包括空洞
    unsigned long        present_pages;    //较少使用，实际可用的页的数目，不包括空洞，通常与spanned_pages相同
    const char        *name;              //较少使用，保存内存域的惯用名称：Normal、DMA、HighMem
} ____cacheline_internodealigned_in_smp;
```

**3. 内存阈值（watermark，也称水位）的初始化**

- 在内核启动或内存热插拔时，会重新计算内存阈值
- 内存阈值：衡量内存的使用情况，有一个专门的内核线程`kswapd0`定期回收内存。**系统内存越大，则阈值越大**
  - 空闲页多于`pages_high`，内存域状况理想
  - 空闲页低于`pages_low`，页需要换出到硬盘
  - 空闲页低于`pages_min`，页回收压力大，即内存域急需空闲页

- `zone->pages_min`、`zone->pages_low`、`zone->pages_high`由`setup_per_zone_pages_min()`初始化
  - `pages_min`可以通过`/proc/sys/vm/min_free_kbytes` 内核选项设置（>=128KB，<=64MB）。初始的典型值计算方式：$pages\_min = 4\sqrt{lowmem\_kbytes}$，其中`lowmem_kbytes`可以认为是系统内存大小
  - pages_low = pages_min * 5  / 4
  - pages_high = pages_min * 3 / 2
- `zone->lowmem_reserve`： **kernel在分配内存时，可能会涉及到多个zone，优先尝试从自己的zone分配，如果失败就会尝试低地址的zone**。每个zone需要自己预留内存
  - 由`setup_per_zone_lowmem_reserve()`初始化，具体算法是：预留内存 = zone管理的页帧数 / 比率
    - 比率由内核参数`/proc/sys/vm/lowmem_reserve_ratio`指定，默认：DMA是256，NORMAL是256，HIGHMEM是32*（在Linux 2.6.24上面是256  32  32）*
    - ratio=256表示有1/256的页帧被保护；如果ratio=1表示有100%的页帧被保护

```
# 4.14内核版本的预留内存分布
$ cat /proc/sys/vm/lowmem_reserve_ratio
256     256     32
```

- 我们可以通过`/proc/zoneinfo`查看具体的内存域信息

```bash
# 1GB内存32位虚拟机的内存域分布（2.6.24内核版本）
# cat /proc/zoneinfo
Node 0, zone      DMA
  pages free     2380
        min      17
        low      21
        high     25
        scanned  0 (a: 0 i: 0)
        spanned  4096
        present  4064
        protection: (0, 873, 1000, 1000)
......
Node 0, zone   Normal
  pages free     220882
        min      936
        low      1170
        high     1404
        scanned  0 (a: 0 i: 0)
        spanned  225280
        present  223520
        protection: (0, 0, 1015, 1015)
......
Node 0, zone  HighMem
  pages free     32520
        min      32
        low      66
        high     100
        scanned  0 (a: 0 i: 0)
        spanned  32766
        present  32511
        protection: (0, 0, 0, 0)
......

# 系统总预留的物理内存(KB) ~= (dma.min + dma32.min + normal.min) * 4
# cat /proc/sys/vm/min_free_kbytes
3816
```

- 上面的例子说明：
  - **存在三个zone：DMA、NORMAL、HIGHMEM**
    - zone[DMA]管理4096个页帧，也就是16MB内存
    - zone[NORMAL]管理225280个页帧，也就是约880MB内存
    - zone[HIGHMEM]管理32766个页帧，也就是约128MB内存
  - **spanned：表示内存域的总页帧数，包括空洞**
  - **present：表示内存域的可用页帧数，不包括空洞**
  - **managed：内存域中被伙伴系统管理的页帧数**
  - **protection：每个区域保留的不能被用户空间分配的页面数目**
  - **预留内存计算** *（在内核2.6.24源码是使用present，而内核4.14使用managed）*
    - protection[dma, normal] = (normal.present) / 256 = 873
    - protection[dma, high] = (normal.present + high.present) / 256 = 1000
    - 也就是说，如果normal内存不够，想在dma中尝试申请page时，此时dma.free > dma.high + protection[dma,normal]，所以可以分配；否则不能分配（代码参考：3.5.5节`zone_watermark_ok()`）

【注】内核参数具体介绍可以看这里：https://www.kernel.org/doc/Documentation/sysctl/vm.txt



**4. 冷热页**

- 热页：页加入到高速缓存；冷页：不在高速缓存中（在2.6.25版本将冷热页合并为一个）
- 冷热页分配器（hot-n-cold allocator）：根据阈值，控制页什么时候被加载进高速缓存中

```
struct zone 
    //用于实现每个CPU的热页列表和冷页列表
    struct per_cpu_pageset    pageset[NR_CPUS];
};

struct per_cpu_pageset {
    struct per_cpu_pages pcp[2];    /* 0: hot.  1: cold */
......
} ____cacheline_aligned_in_smp;

struct per_cpu_pages {
    int count;        /* number of pages in the list */
    int high;        /* high watermark, emptying needed */
    int batch;        /* chunk size for buddy add/remove */
    struct list_head list;    /* the list of pages */
};
```

![image-20220922081605642](C:\Users\THINKPAD\Desktop\learning\learning\image-20220922081605642.png)

**5. 页帧**

- **页帧**：内存分配的最小单位，IA-32系统标准页长度为**4KB**。每个页会创建一个`struct page`实例
  - 注意实例中结构体尽可能小，利用union


```C++
struct page {
        unsigned long flags;    /* 用于描述页的属性，原子标志，有些情况下会异步更新 */
        atomic_t _count;        /* 引用计数，内核中引用该页的次数。其值为0可以删除 */
        union {
            atomic_t _mapcount; /* 页表中有多少项指向该页
                                 * 用于表示页是否已经映射，还用于限制逆向映射搜索。
                                 */
            unsigned int inuse; /* 用于SLUB分配器：对象的数目 */
    };
    union {
        struct {
            unsigned long private; /* 由映射私有，不透明数据：
                                    * 如果设置了PagePrivate，通常用于buffer_heads；
                                    * 如果设置了PageSwapCache，则用于swp_entry_t；
                                    * 如果设置了PG_buddy，则用于表示伙伴系统中的阶。
                                    */
            struct address_space *mapping; /* mapping指定了页帧所在的地址空间。index是页帧映射内部的偏移量
                                            * 如果最低位为0，则指向inode
                                            * address_space，或为NULL。
                                            * 如果页映射为匿名内存，最低位置位，
                                            * 而且该指针指向anon_vma对象：
                                            * 参见下文的PAGE_MAPPING_ANON。
                                            */
        };
        ...
        struct kmem_cache *slab; /* 用于SLUB分配器：指向slab的指针 */
        struct page *first_page; /* 用于复合页的尾页，指向首页 */
    };
    union {
        pgoff_t index; /* 在映射内的偏移量 */
        void *freelist; /* SLUB: freelist req. slab lock */
    };
    struct list_head lru; /* 换出页列表，例如由zone->lru_lock保护的active_list!*/
    
    #if defined(WANT_PAGE_VIRTUAL)
        void *virtual; /* 内核虚拟地址（如果没有映射则为NULL，即高端内存） */
    #endif /* WANT_PAGE_VIRTUAL */
};
```

- 重要的页标志`page->flags`。由一些原子操作设置相应比特位
  - `PG_locked`：页是否锁定
  - `PG_error`：该页的IO操作期间发生错误
  - `PG_referenced`和`PG_active`：控制页的活跃次数，用于页交换
  - `PG_uptodate`：页的数据已经从块设备读取，期间没有出错
  - `PG_dirty`：页内容发生改变
  - `PG_lru`：用于实现页面回收和切换
  - `PG_highmem`：页在高端内存中，无法持久映射到内核内存中
  - `PG_private`：page的private成员非空时设置
  - `PG_writeback`：页内容正在向块设备回写
  - `PG_slab`：页是slab分配器的一部分
  - `PG_swapcache`：页处于交换缓存。此时private包含一个类型为swap_entry_t的项
  - `PG_reclaim`：内核决定回收某个特定的页后，设置PG_reclaim标志通知
  - `PG_buddy`：页空闲且包含在伙伴系统的列表中
  - `PG_compound`：页属于一个更大的复合页，复合页由多个毗连的普通页组成



## 3.3 页表

### 3.3.1 数据结构

**1. 内存地址的分解**

![image-20220930081345790](C:\Users\THINKPAD\Desktop\learning\learning\image-20220930081345790.png)

- 虚拟内存地址分为5个部分：**PGD（全局页目录）、PUD（上层页目录）、PMD（中间页目录）、PTE（页表）、Offset（偏移）**。PGD寻址512个PUD，以此类推。
  - X86 32位（二级页表）：PGD=31\~22、PTE=21\~12、Offset=11\~0
  - X86 32位PAE模式（三级页表）：PGD=31\~30、PMD=29\~21、PTE=20\~12、Offset=11\~0
  - X86 64位（四级页表）：PGD=47\~39、PUD=38\~30、PMD=29\~21、PTE=20\~12、Offset=11\~0

![image-20221002071308100](C:\Users\THINKPAD\Desktop\learning\learning\image-20221002071308100.png)



**2. 页表的格式**

- 以AMD64体系结构为例，根据intel手册，页表项的结构如下：

![image-20221002071946912](C:\Users\THINKPAD\Desktop\learning\learning\image-20221002071946912.png)

- 因此，在Linux内核中，页表项定义为一个64 bit的struct
  - 注：定义为struct目的是只允许相关辅助函数处理

```
typedef struct { unsigned long pte; } pte_t;
typedef struct { unsigned long pmd; } pmd_t;
typedef struct { unsigned long pud; } pud_t;
typedef struct { unsigned long pgd; } pgd_t;
```

- 页表项的位信息示例：

```
#define _PAGE_PRESENT    0x001    //页是否存在于内存中，即是否被交换到磁盘上了
#define _PAGE_RW    0x002        //允许读写或禁止读写
#define _PAGE_USER    0x004        //允许用户空间代码访问该页
#define _PAGE_PWT    0x008        //Page-level write-through
#define _PAGE_PCD    0x010        //Page-level cache disable
#define _PAGE_ACCESSED    0x020    //CPU每次访问页时，会设置该位
#define _PAGE_DIRTY    0x040        //页的内容是否被修改过
#define _PAGE_FILE    0x040         //页表项属于非线性映射
#define _PAGE_PSE    0x080         /* 2MB page */
#define _PAGE_PROTNONE    0x080     /* If not present */
#define _PAGE_GLOBAL    0x100     /* Global TLB entry */
```

- 以`pte_t`为例，内核定义了一系列辅助函数操作页表项，用于比特位的置位：

```
//地址对齐到页边界（地址舍入到下一页的起始处，一定是页大小的倍数）
#define PAGE_ALIGN(addr)    (((addr)+PAGE_SIZE-1)&PAGE_MASK)

//读取页表项
#define pte_val(x)    ((x).pte)
//设置页表项
#define __pte(x) ((pte_t) { (x) } )
//从内存指针和页表项获得下一级页表的地址
#define pte_index(address) (((address) >> PAGE_SHIFT) & (PTRS_PER_PTE - 1))
//删除页表项，通常置0
#define pte_clear(mm,addr,xp)    do { set_pte_at(mm, addr, xp, __pte(0)); } while (0)
//检查的页是否在内存中
#define pte_present(x)    (pte_val(x) & (_PAGE_PRESENT | _PAGE_PROTNONE))

static inline void set_pte(pte_t *dst, pte_t val) {
    pte_val(*dst) = pte_val(val);
}
//检查的页是否设置了DIRTY、ACCESSED、RW位
static inline int pte_dirty(pte_t pte)        { return pte_val(pte) & _PAGE_DIRTY; }
static inline int pte_young(pte_t pte)        { return pte_val(pte) & _PAGE_ACCESSED; }
static inline int pte_write(pte_t pte)        { return pte_val(pte) & _PAGE_RW; }
//为页设置DIRTY、ACCESSED、RW位
static inline pte_t pte_mkdirty(pte_t pte)    { set_pte(&pte, __pte(pte_val(pte) | _PAGE_DIRTY)); return pte; }
static inline pte_t pte_mkyoung(pte_t pte)    { set_pte(&pte, __pte(pte_val(pte) | _PAGE_ACCESSED)); return pte; }
static inline pte_t pte_mkwrite(pte_t pte)    { set_pte(&pte, __pte(pte_val(pte) | _PAGE_RW)); return pte; }
```

- **物理地址和虚拟地址的转换**
  - 内核源码中有定义一系列的转换函数，用户程序访问的虚拟页通过页表转为物理页帧
  - 命名规范：page（页）、pfn（页帧）、virt（虚拟地址）、phys（物理地址）
  - 转换规则
    - virt = phys - PHYS_OFFSET + PAGE_OFFSET
    - pfn = phys / 4096
    - page = mem_map + (pfn - PHYS_PFN_OFFSET)

```
//内核空间（非高端内存域）的虚拟地址到物理地址的线性映射。例如0xC0100000映射到0x00100000物理地址
#define __pa(x)            ((unsigned long)(x)-PAGE_OFFSET)
#define __va(x)            ((void *)((unsigned long)(x)+PAGE_OFFSET))

//物理地址和虚拟地址互转
#define __virt_to_phys(x) (((phys_addr_t)(x) - PAGE_OFFSET + PHYS_OFFSET))
#define __phys_to_virt(x) ((unsignedlong)((x) - PHYS_OFFSET + PAGE_OFFSET))

//页帧到物理页的映射。mem_map是page结构体数组基址，加上物理页帧距离起始页帧的偏移即当前对应的虚拟页地址
#define pfn_to_page(pfn) (mem_map + ((pfn) - PHYS_PFN_OFFSET))
#define page_to_pfn(page) ((unsigned long)((page) - mem_map) + PHYS_PFN_OFFSET)

//内核虚拟地址和页帧互转
#define virt_to_pfn(kaddr)    (__pa(kaddr) >> PAGE_SHIFT)
#define pfn_to_virt(pfn)    __va((pfn) << PAGE_SHIFT)

//内核虚拟地址和页互转
#define virt_to_page(kaddr)    pfn_to_page(__pa(kaddr) >> PAGE_SHIFT)

//页帧、物理地址互转
#define PFN_ALIGN(x)    (((unsigned long)(x) + (PAGE_SIZE - 1)) & PAGE_MASK)
#define PFN_UP(x)    (((x) + PAGE_SIZE-1) >> PAGE_SHIFT)
#define PFN_DOWN(x)    ((x) >> PAGE_SHIFT)
#define PFN_PHYS(x)    ((x) << PAGE_SHIFT)
```



## 3.4 初始化内存管理（单内存结点UMA系统）

### 3.4.1 建立数据结构

- **系统初始化过程`start_kernel`**：建立结点和内存域的数据结构、初始化内存管理的分配器（bootmem、伙伴系统等）

![image-20221002174530656](C:\Users\THINKPAD\Desktop\learning\learning\image-20221002174530656.png)

- `build_all_zonelists()`：建立结点和内存域的数据结构
  - `__build_all_zonelists()`：对系统中的各个NUMA结点分别调用build_zonelists()
  - `build_zonelists()`：内存域建立等级次序，依照这个次序分配内存（ZONE_HIGHMEM最廉价，ZONE_DMA最昂贵）
  - `build_zonelists_node()`：初始化各结点的内存域`zones`和备用列表`node_zonelists`

```C++
static int __build_all_zonelists(void *dummy)
{
    int nid;

    for_each_online_node(nid) {
        //各个NUMA结点的pg_data_t实例，UMA系统即config_page_data的地址
        pg_data_t *pgdat = NODE_DATA(nid);
        //对系统中的各个NUMA节点分别调用build_zonelists
        build_zonelists(pgdat);
        build_zonelist_cache(pgdat);
    }
    return 0;
}

static void build_zonelists(pg_data_t *pgdat)
{
    int node, local_node;
    enum zone_type i,j;

    local_node = pgdat->node_id;
    //迭代所有的内存域，顺序：ZONE_DMA、ZONE_NORMAL、ZONE_HIGHMEM
    for (i = 0; i < MAX_NR_ZONES; i++) {
        struct zonelist *zonelist;
        zonelist = pgdat->node_zonelists + i;
        //备用列表node_zonelists添加自己结点的内存域
         j = build_zonelists_node(pgdat, zonelist, 0, i);
         //备用列表node_zonelists添加其它结点[local_node+1, MAX_NUMNODES)的内存域
        for (node = local_node + 1; node < MAX_NUMNODES; node++) {
            if (!node_online(node))
                continue;
            j = build_zonelists_node(NODE_DATA(node), zonelist, j, i);
        }
        //备用列表node_zonelists添加其它结点[0, local_node-1]的内存域
        for (node = 0; node < local_node; node++) {
            if (!node_online(node))
                continue;
            j = build_zonelists_node(NODE_DATA(node), zonelist, j, i);
        }

        zonelist->zones[j] = NULL;
    }
}

static int build_zonelists_node(pg_data_t *pgdat, struct zonelist *zonelist,
                int nr_zones, enum zone_type zone_type)
{
    struct zone *zone;

    BUG_ON(zone_type >= MAX_NR_ZONES);
    zone_type++;

    do {
        //zone_type即内存域类型（DMA、NORMAL、HIGHMEM），值越小表示内存域越昂贵
        //每次迭代向备用列表添加一个更昂贵的内存域，表示可以向这个内存域申请页
        zone_type--;
        zone = pgdat->node_zones + zone_type;
        //这里先确认内存域中有页存在
        if (populated_zone(zone)) {
            zonelist->zones[nr_zones++] = zone;
            check_highest_zone(zone_type);
        }

    } while (zone_type);
    return nr_zones;
}
```

【例】NUMA 4结点系统中，为结点2建立的备用列表node_zonelists

- A=(NUMA)结点0、B=(NUMA)结点1、C=(NUMA)结点2、D=(NUMA)结点3
- 0=DMA内存域、1=普通内存域、2=高端内存域

![image-20221002190221270](C:\Users\THINKPAD\Desktop\learning\learning\image-20221002190221270.png)

【说明】结点2的普通内存域申请内存时，先从C1（结点2的ZONE_NORMAL）开始申请，然后是C0（结点2的ZONE_DMA），以此类推

- 优先从本结点开始申请，因为CPU与本地内存的距离最近
- 高端内存域最廉价，DMA内存域最昂贵。高端内存域无法申请到页，则向低一级的普通内存域中申请
- 本地结点申请不到内存，再向其它内存域申请页



### 3.4.2 32位和64位体系结构

**1. 内核在内存中的布局**

![image-20221002211136912](C:\Users\THINKPAD\Desktop\learning\learning\image-20221002211136912.png)

- IA-32体系物理内存最低几兆字节的布局
  - 0\~0x1000：第一个页帧，通常保留给BIOS
  - 0x1000\~0x9e800：系统保留，原则上<640KB的内核可以装载
  - 0x9e800\~0x100000：一般用于映射各种ROM
  - 0x100000\~end：IA-32的内核起始地址，注意内核地址空间需要连续
    - \_text\~\_etext：代码段起始和结束地址，包含了编译后的内核代码
    - \_etext\~\_edata：数据段起始和结束地址，保存大量内核变量
    - \_edata\~\_end：内核初始化数据，在启动过程结束后不再需要，大部分数据可以释放
- 64位系统也可以得到类似的信息，物理内存映射可以查看`/proc/iomem`

```
# cat /proc/iomem
00000000-00000fff : Reserved
00001000-000867ff : System RAM
00086800-0009ffff : Reserved
000a0000-000bffff : PCI Bus 0000:00
000c0000-000c7fff : Video ROM
  000c4000-000c7fff : PCI Bus 0000:00
000c8000-000d09ff : Adapter ROM
000d1000-000d99ff : Adapter ROM
000e0000-000fffff : Reserved
  000f0000-000fffff : System ROM
00100000-5e407fff : System RAM
  3e000000-5dffffff : Crash kernel
......
```



**2. 内存初始化步骤`setup_arch()`**

![image-20221003074345751](C:\Users\THINKPAD\Desktop\learning\learning\image-20221003074345751.png)

![image-20221003080612489](C:\Users\THINKPAD\Desktop\learning\learning\image-20221003080612489.png)

- `machine_specific_memory_setup()`：创建一个列表，包括系统占据的内存区和空闲内存区

```
# dmesg
[    0.000000] e820: BIOS-provided physical RAM map:
[    0.000000] BIOS-e820: [mem 0x0000000000000000-0x000000000009fbff] usable
[    0.000000] BIOS-e820: [mem 0x000000000009fc00-0x000000000009ffff] reserved
[    0.000000] BIOS-e820: [mem 0x00000000000f0000-0x00000000000fffff] reserved
[    0.000000] BIOS-e820: [mem 0x0000000000100000-0x00000000bffdbfff] usable
[    0.000000] BIOS-e820: [mem 0x00000000bffdc000-0x00000000bfffffff] reserved
[    0.000000] BIOS-e820: [mem 0x00000000feffc000-0x00000000feffffff] reserved
[    0.000000] BIOS-e820: [mem 0x00000000fffc0000-0x00000000ffffffff] reserved
[    0.000000] BIOS-e820: [mem 0x0000000100000000-0x000000023fffffff] usable
```

- `parse_early_param()`：用于分析命令行，主要关注类似mem=XXX、highmem=XXX或memmap=XXX之类的参数，只适用于比较古老的计算机
- `setup_memory()`：确定可用物理页数目、初始化bootmem分配器、分配内存区（如运行第一个用户空间过程所需的最初的RAM磁盘）
- `paging_init()`：初始化内核页表并启用内存分页
- `zone_sizes_init()`：初始化所有节点的`pg_data_t`结构体



**3. 分页机制的初始化`paging_init()`**

- **地址空间的划分**

  - IA-32体系中，虚拟地址空间和物理地址空间是3:1的关系。**内核空间直接映射到物理内存中（共享）；用户空间通过页表映射（不共享）**

  ![image-20221003081014820](C:\Users\THINKPAD\Desktop\learning\learning\image-20221003081014820.png)

  - 虚拟地址空间的**内核地址空间布局：0xC0000000~4GB**

    - 0~896MB：非高端内存域，可以线性映射到物理内存

    ```
    #define __pa(x)        ((unsigned long)(x)-PAGE_OFFSET)
    #define __va(x)        ((void *)((unsigned long)(x)+PAGE_OFFSET))
    ```

    - 896MB~1024MB：高端内存域，不能直接映射到页帧，分3个部分：
      - VMALLOC：分配虚拟内存中连续、但物理内存中不连续的内存区（比如动态加载模块时，会出现内存碎片）
      - 持久映射：用于将高端内存域中的非持久页映射到内核中（3.5.8节）
      - 固定映射：虚拟页可以固定映射到物理地址固定页帧，具体映射位置可以自行定义

![image-20221003081704159](C:\Users\THINKPAD\Desktop\learning\learning\image-20221003081704159.png)



- **`paging_init()`过程**
  - `pagetable_init()`：初始化系统的页表，启用扩展（对超大内存页支持、__PAGE_GLOBAL）
  - `kernel_physical_mapping_init()`：将物理内存页映射到虚拟地址空间PAGE_OFFSET开始的位置
  - 初始化固定映射和持久映射的内存区
  - cr3寄存器指向全局页目录的指针
  - TLB缓存刷出启动时分配的内存地址数据
  - 初始化全局变量`kernel_pte`，高端内存域将页映射到内核地址空间时，会使用该变量

![image-20221003083221232](C:\Users\THINKPAD\Desktop\learning\learning\image-20221003083221232.png)



- **冷热缓存的初始化**
  - **冷热页目的：控制L2缓存的页的数目**
  - 由`zone_pcp_init()`完成初始化，通过`zone_bathsize()`获取batch大小，batch大小是$2^n-1$的形式
    - `zone_bathsize()`：batch计算结果大约是内存域页数的0.025%
  - `batch`：用于设置冷热页的上限，控制缓存中页的数目。
    - IA-32体系，每个CPU对应的L2缓存（0.25MB\~2MB）大概是各CPU配备内存（1GB\~2GB）的千分之一
    - **内核控制缓存平均数量大约是4*batch，即千分之一内存**
    - 热页：上限为6*batch
    - 冷页：上限为2*batch

```
static __meminit void zone_pcp_init(struct zone *zone)
{
    int cpu;
    //计算batch的值，大约是内存域页数的0.025%
    unsigned long batch = zone_batchsize(zone);

    for (cpu = 0; cpu < NR_CPUS; cpu++) {
        //设置冷热页
        setup_pageset(zone_pcp(zone,cpu), batch);
    }
    if (zone->present_pages)
        printk(KERN_DEBUG "  %s zone: %lu pages, LIFO batch:%lu\n",
            zone->name, zone->present_pages, batch);
}

//这个函数用于计算batch大小，计算结果batch值大约是内存域页数的0.025%
static int zone_batchsize(struct zone *zone)
{
    int batch;

    batch = zone->present_pages / 1024;
    if (batch * PAGE_SIZE > 512 * 1024)
        batch = (512 * 1024) / PAGE_SIZE;
    batch /= 4;        /* We effectively *= 4 below */
    if (batch < 1)
        batch = 1;

    batch = (1 << (fls(batch + batch/2)-1)) - 1;

    return batch;
}

//设置冷热页
inline void setup_pageset(struct per_cpu_pageset *p, unsigned long batch)
{
    struct per_cpu_pages *pcp;

    memset(p, 0, sizeof(*p));

    pcp = &p->pcp[0];        /* hot */
    pcp->count = 0;
    pcp->high = 6 * batch;
    pcp->batch = max(1UL, 1 * batch);
    INIT_LIST_HEAD(&pcp->list);

    pcp = &p->pcp[1];        /* cold*/
    pcp->count = 0;
    pcp->high = 2 * batch;
    pcp->batch = max(1UL, batch/2);
    INIT_LIST_HEAD(&pcp->list);
}
```

【结果】可以在dmesg看到各个内存域的页数以及计算出的batch值。注意DMA内存域均为冷页，不放到缓存中

```
$ dmesg | grep batch
[    0.000000]   DMA zone: 3998 pages, LIFO batch:0
[    0.000000]   DMA32 zone: 782300 pages, LIFO batch:31
[    0.000000]   Normal zone: 1310720 pages, LIFO batch:31
```



- **注册活动内存区**
  - IA-32体系：使用`zone_sizes_init()`设置各个内存域的页帧数，并初始化活动内存区
  - AMD64体系：使用`e820_register_active_regions()`注册活动内存区，使用`paging_init()`设置各内存域的页帧数

```
#define MAX_DMA_ADDRESS  (PAGE_OFFSET+0x1000000)

//存储不同内存域的边界
void __init zone_sizes_init(void)
{
    unsigned long max_zone_pfns[MAX_NR_ZONES];
    memset(max_zone_pfns, 0, sizeof(max_zone_pfns));
    
    //通过virt_to_phys转换获得物理地址
    max_zone_pfns[ZONE_DMA] = virt_to_phys((char *)MAX_DMA_ADDRESS) >> PAGE_SHIFT;
    max_zone_pfns[ZONE_NORMAL] = max_low_pfn;
#ifdef CONFIG_HIGHMEM
    max_zone_pfns[ZONE_HIGHMEM] = highend_pfn;
    add_active_range(0, 0, highend_pfn);
#else
    add_active_range(0, 0, max_low_pfn);
#endif

    free_area_init_nodes(max_zone_pfns);
}
```

- ZONE_DMA：对应虚拟地址[PAGE_OFFSET, PAGE_OFFSET+16MB]，最后获得页帧数：4096个页
- ZONE_NORMAL：含有max_low_pfn个页帧，其中max_low_pfn是低端内存最高页号，通常<=896MB
- ZONE_HIGHMEM：含有highend_pfn个页帧，其中highend_pfn是高端内存的最高页号
- `add_active_range()`：注册合并活动内存区（即不含空洞的连续内存）到全局变量`early_node_map`中。当有两个毗邻的内存，会合并为一个。IA-32体系中，会把0\~highend_pfn的页帧注册到活动内存区数组中
  - `early_node_map`：是一个node_active_region数组，里边记录了所有的不含空洞的连续内存，数组含有nr_nodemap_entries个元素。结构体如下：

```
struct node_active_region {
    unsigned long start_pfn;   //连续内存区的第一帧
    unsigned long end_pfn;     //连续内存区的最后一帧
    int nid;                   //内存区所属节点的NUMA ID。UMA系统为0
};
```

【结果】在dmesg中，可以看到各个内存域的范围，以及early_node_map连续内存数组

```
[    0.020319] Zone ranges:
[    0.020320]   DMA      [mem 0x0000000000001000-0x0000000000ffffff]
[    0.020321]   DMA32    [mem 0x0000000001000000-0x00000000ffffffff]
[    0.020322]   Normal   [mem 0x0000000100000000-0x000000407fffffff]
[    0.020323]   Device   empty
[    0.020323] Movable zone start for each node
[    0.020326] Early memory node ranges
[    0.020326]   node   0: [mem 0x0000000000001000-0x0000000000085fff]
[    0.020327]   node   0: [mem 0x0000000000100000-0x000000005e407fff]
[    0.020328]   node   0: [mem 0x000000005e629000-0x00000000679edfff]
[    0.020328]   node   0: [mem 0x000000006a2ff000-0x000000006a681fff]
[    0.020329]   node   0: [mem 0x000000006d7c6000-0x000000006fffffff]
[    0.020329]   node   0: [mem 0x0000000100000000-0x000000207fffffff]
[    0.020337]   node   1: [mem 0x0000002080000000-0x000000407fffffff]
```



- **AMD64地址空间**
  - 用户态虚拟地址空间（四级页表）的仅用到**低47位**，因此有一部分空间是预留的（[47,63]要么全0要么全1）
    - **用户地址空间：0\~0x00007FFFFFFFFFFF**
    - **内核地址空间：0xFFFF800000000000 ~ 0xFFFFFFFFFFFFFFFF**
      - 0xFFFF800000000000\~PAGE_OFFSET（0xFFFF810000000000）：空洞，未使用
      - PAGE_OFFSET\~PAGE_OFFSET+MAXMEM：一致映射页帧，$2^{46}$字节，64TB内存
      - VMALLOC_START\~VMALLOC_END：VMALLOC内存区，大概200GB字节
      - VMM_START\~：VMM内存区（虚拟内存映射），1TB。当内核使用稀疏内存模型时，该内存区有用
      - START_KERNEL_MAP\~MODULES_VADDR：内核代码段，长度为KERNEL_TEXT_SIZE，40MB
      - MODULES_VADDR\~MODULES_END：映射模块，长度为MODULES_LEN，大约1920MB

![image-20221003133303245](C:\Users\THINKPAD\Desktop\learning\learning\image-20221003133303245.png)

![image-20221003133538009](C:\Users\THINKPAD\Desktop\learning\learning\image-20221003133538009.png)



### 3.4.3 启动过程期间的内存管理

【背景】启动过程中，由于内存管理（如伙伴系统）尚未初始化，因此分配器`bootmem`采用最简单的方案，通过逐位扫描获取一个连续的内存页位置（first-fit）进行分配内存。初始化完成后要停用`bootmem`

**1. 数据结构**

- UMA系统上只有一个bootmem分配器，分配器管理的数据记录在bootmem_data中
- NUMA系统上有多个bootmem_t实例

```
typedef struct bootmem_data {
    unsigned long node_boot_start;  //保存系统第一个页帧的编号，大多数情况为0
    unsigned long node_low_pfn;     //是可以直接管理的物理地址空间的最后一页帧编号，即ZONE_NORMAL的结束页帧
    void *node_bootmem_map;         //指向存储分配位图的内存区的指针
    unsigned long last_offset;      //页帧内部的偏移量（也就是说可以分配<4KB的内存区）
    unsigned long last_pos;         //上一个分配的页帧的编号
    unsigned long last_success;        //上一次成功分配内存的位置，新的分配由此开始
    struct list_head list;
} bootmem_data_t;
```



**2. 初始化位图**

- IA-32的初始化：通过`setup_memory()`找到低端内存区最大的页帧号。利用体系结构相关的代码，标出低端内存区哪些页是可用的。另外，需要预留出一些不可用的内存区。

- AMD64的初始化：与IA-32类似，入口是`config_initmem()`

```
//IA-32体系初始化bootmem分配器
void __init setup_bootmem_allocator(void)
{
......
    bootmap_size = init_bootmem(min_low_pfn, max_low_pfn);
    register_bootmem_low_pages(max_low_pfn);

    //将bootmem自身要使用的空间预留出来，不能使用
    reserve_bootmem(__pa_symbol(_text), (PFN_PHYS(min_low_pfn) +
             bootmap_size + PAGE_SIZE-1) - __pa_symbol(_text));

    //page 0预留出来，不能使用
    reserve_bootmem(0, PAGE_SIZE);
......
}

//初始化bootmem分配器，输入pgdat=NODE_DATA(0), mapstart=min_low_pfn, start=0, end=max_low_pfn
static unsigned long __init init_bootmem_core(pg_data_t *pgdat,
    unsigned long mapstart, unsigned long start, unsigned long end)
{
    bootmem_data_t *bdata = pgdat->bdata;
    unsigned long mapsize;

    //将setup_memory()检测到低端内存区的页帧范围记录到bootmem_data_t中
    bdata->node_bootmem_map = phys_to_virt(PFN_PHYS(mapstart));
    bdata->node_boot_start = PFN_PHYS(start);
    bdata->node_low_pfn = end;
    link_bootmem(bdata);

    //返回boot bitmap的大小，向上对齐8的倍数
    mapsize = get_mapsize(bdata);
    memset(bdata->node_bootmem_map, 0xff, mapsize);

    return mapsize;
}

//从e820表中找到可用的页帧，记录到bdata->node_bootmem_map位图中
void __init register_bootmem_low_pages(unsigned long max_low_pfn)
{
......
    //e820表是通过int 0x15中断获取的内存布局
    for (i = 0; i < e820.nr_map; i++) {
        curr_pfn = PFN_UP(e820.map[i].addr);
        last_pfn = PFN_DOWN(e820.map[i].addr + e820.map[i].size);
......
        size = last_pfn - curr_pfn;
        //这里将可用的页标注出来设置到bdata->node_bootmem_map位图中
        free_bootmem(PFN_PHYS(curr_pfn), PFN_PHYS(size));
    }
}

//将不可用的页帧预留出来，设置到bdata->node_bootmem_map位图中
static void __init reserve_bootmem_core(bootmem_data_t *bdata, unsigned long addr,
                    unsigned long size)
{
    sidx = PFN_DOWN(addr - bdata->node_boot_start);
    eidx = PFN_UP(addr + size - bdata->node_boot_start);

    for (i = sidx; i < eidx; i++)
        if (test_and_set_bit(i, bdata->node_bootmem_map)) {
#ifdef CONFIG_DEBUG_BOOTMEM
            printk("hm, page %08lx reserved twice.\n", i*PAGE_SIZE);
#endif
        }
}
```



**3. 对内核的接口**

- **分配内存`alloc_bootmem()`**
  - 从goal开始，扫描位图，查找满足分配的空闲内存区
  - 如果满足分配，则页帧在位图对应的比特位置1，更新last_pos和last_offset供下次分配；不满足则重新扫描位图
    - 目标页帧紧接着上一次分配的页帧，可以从上一次页帧的OFFSET处继续往下分配（也就是说分配时不用对齐内存，可以分配比4K小的内存区）
    - 如果不紧接着上一次分配的页帧，更新位图和last_pos、last_offset

```
void * __init
__alloc_bootmem_core(struct bootmem_data *bdata, unsigned long size,
          unsigned long align, unsigned long goal, unsigned long limit)
{
    //一些检查过程，内容忽略
......
    //计算从哪里开始分配，需要分配多少个页帧
    preferred = PFN_DOWN(ALIGN(preferred, align)) + offset;
    areasize = (size + PAGE_SIZE-1) / PAGE_SIZE;
    incr = align >> PAGE_SHIFT ? : 1;

//扫描位图，查找满足条件的空闲内存区。满足跳转found，不满足跳转fail_block重新扫描
restart_scan:
    for (i = preferred; i < eidx; i += incr) {
        unsigned long j;
        i = find_next_zero_bit(bdata->node_bootmem_map, eidx, i);
        i = ALIGN(i, incr);
        if (i >= eidx)
            break;
        if (test_bit(i, bdata->node_bootmem_map))
            continue;
        for (j = i + 1; j < i + areasize; ++j) {
            if (j >= eidx)
                goto fail_block;
            if (test_bit(j, bdata->node_bootmem_map))
                goto fail_block;
        }
        start = i;
        goto found;
    fail_block:
        i = ALIGN(j, incr);
    }

    if (preferred > offset) {
        preferred = offset;
        goto restart_scan;
    }
    return NULL;

found:
    bdata->last_success = PFN_PHYS(start);
    BUG_ON(start >= eidx);

    //如果目标页帧紧接着上一次分配的页帧，可以从上一次页帧的OFFSET处继续往下分配
    //分配完成后last_pos和last_offset更新
    if (align < PAGE_SIZE &&
        bdata->last_offset && bdata->last_pos+1 == start) {
        offset = ALIGN(bdata->last_offset, align);
        BUG_ON(offset > PAGE_SIZE);
        remaining_size = PAGE_SIZE - offset;
        //区分分配的内存比页帧剩余内存小的情况
        if (size < remaining_size) {
            areasize = 0;
            /* last_pos unchanged */
            bdata->last_offset = offset + size;
            ret = phys_to_virt(bdata->last_pos * PAGE_SIZE +
                       offset +
                       bdata->node_boot_start);
        } else {
            remaining_size = size - remaining_size;
            areasize = (remaining_size + PAGE_SIZE-1) / PAGE_SIZE;
            ret = phys_to_virt(bdata->last_pos * PAGE_SIZE +
                       offset +
                       bdata->node_boot_start);
            bdata->last_pos = start + areasize - 1;
            bdata->last_offset = remaining_size;
        }
        bdata->last_offset &= ~PAGE_MASK;
    } else {
        bdata->last_pos = start + areasize - 1;
        bdata->last_offset = size & ~PAGE_MASK;
        ret = phys_to_virt(start * PAGE_SIZE + bdata->node_boot_start);
    }

    //新分配的目标页，位图置1
    for (i = start; i < start + areasize; i++)
        if (unlikely(test_and_set_bit(i, bdata->node_bootmem_map)))
            BUG();
    memset(ret, 0, size);
    return ret;
}
```



- **释放内存`free_bootmem()`**
  - 将释放的页在位图bdata->node_bootmem_map里面置0

```
static void __init free_bootmem_core(bootmem_data_t *bdata, unsigned long addr,
                     unsigned long size)
{
......
    sidx = PFN_UP(addr) - PFN_DOWN(bdata->node_boot_start);
    eidx = PFN_DOWN(addr + size - bdata->node_boot_start);

    for (i = sidx; i < eidx; i++) {
        if (unlikely(!test_and_clear_bit(i, bdata->node_bootmem_map)))
            BUG();
    }
}
```



**4. 停用bootmem分配器**

- 系统初始化完成，停用bootmem分配器，使用伙伴系统分配器接管内存管理
- 调用标准函数__free_page()，将bootmem使用的内存和bootmem自身占据的内存释放

```
static unsigned long __init free_all_bootmem_core(pg_data_t *pgdat)
{
    count = 0;
    
    pfn = PFN_DOWN(bdata->node_boot_start);
    idx = bdata->node_low_pfn - pfn;
    map = bdata->node_bootmem_map;
......    
    //根据位图bdata，释放bootmem使用的内存
    for (i = 0; i < idx; ) {
        unsigned long m;

        page = pfn_to_page(pfn);
        for (m = 1; m && i < idx; m<<=1, page++, i++) {
            if (v & m) {
                count++;
                __free_pages_bootmem(page, 0);
            }
        }
        pfn += BITS_PER_LONG;
    }
    total += count;

    //释放bootmem自身空间
    page = virt_to_page(bdata->node_bootmem_map);
    count = 0;
    idx = (get_mapsize(bdata) + PAGE_SIZE-1) >> PAGE_SHIFT;
    for (i = 0; i < idx; i++, page++) {
        __free_pages_bootmem(page, 0);
        count++;
    }
    total += count;
    bdata->node_bootmem_map = NULL;

    return total;
}
```



**5. 释放初始化数据**

- 很多内核代码块和数据表只在系统初始化阶段需要（例如链接到内核中的驱动程序），因此可以释放掉
- 内核提供了`__init`和`__initcall`，用来标记这些初始化的函数和数据

```
//标记初始化的代码段和数据段
#define __init        __attribute__ ((__section__ (".init.text"))) __cold
#define __initdata    __attribute__ ((__section__ (".init.data")))
```

- 启动过程最后使用`free_initmem()`释放初始化的内存区，并将相关的页返回给伙伴系统。紧接着`init`作为系统第一个进程启动

```
# dmesg
[    5.921906] Freeing unused kernel image (initmem) memory: 2392K
[    5.931641] Write protecting the kernel read-only data: 24576k
[    5.932198] Freeing unused kernel image (text/rodata gap) memory: 2036K
[    5.932307] Freeing unused kernel image (rodata/data gap) memory: 364K
[    5.932313] Run /init as init process
```



## 3.5 物理内存的管理

### 伙伴系统回顾（第一章）

- **伙伴系统**：Linux内核引入**伙伴系统算法(buddy system)**管理空闲内存块，某种程度上减少了内存碎片(但无法完全消除)
  - 系统的空闲内存块总是两两分组的，每组的两个内存块称为**伙伴**。伙伴的分配是彼此独立的
  - 所有空闲页框默认分组为11个**块链表**，每个块链表分别包含1，2，4，8，16，32，64，128，256，512和1024个连续页框的页框块。应用程序最大可以申请1024个连续页框（对应4MB大小的连续内存）
  - **块申请**：从块链表查找空闲块。如果没找到，向更上级的链表依次查找内存块：内存块**分裂**为两部分，一块分配给应用，另一块加入块链表中。如果实在没有，返回错误
  - **块释放**：内核将伙伴**合并**为更大的内存块放回到伙伴列表中，即内存块分裂的逆过程

![image-20221004121835651](C:\Users\THINKPAD\Desktop\learning\learning\image-20221004121835651.png)



### 3.5.1 伙伴系统的数据结构

- 每个内存域都关联一个`struct zone`实例，其中包含伙伴数据的主要数组`free_area`，`MAX_ORDER=11`即对应11种**空闲页链表**
- `free_area`指定每阶(order)的空闲页链表。**页链表内包含大小相同的连续内存区**
  - **阶**：第0个链表包含的内存区为单页，第1个链表为两页，第2个链表为四页，以此类推
  - **过程**：内存申请时，会将未使用的一半内存块加入到对应的空闲页链表中；内存释放时会从空闲页链表移除

```
struct zone {
    struct free_area free_area[MAX_ORDER];          //伙伴系统划分为11个不同长度的空闲区域
};

struct free_area {
    struct list_head    free_list[MIGRATE_TYPES];   //用于连接空闲页的链表。这里MIGRATE_TYPES与迁移类型有关，后面会讲到
    unsigned long        nr_free;                   //当前内存区中空闲页块的数目
};
```

![image-20221004123431105](C:\Users\THINKPAD\Desktop\learning\learning\image-20221004123431105.png)

【注】**伙伴系统负责同一个结点内存域的内存管理**。伙伴系统之间也是通过**备用列表**连起来的，先尝试本结点内存域，再尝试另一个结点（图3-10）



### 3.5.2 避免碎片

【背景】虽然一个双向链表可以满足伙伴系统的实现，但是**系统长期运行还是会产生很多碎片**。极端情况下，很多小碎片导致无法申请大的连续内存

**1. 页的迁移类型**

- **按页的可移动性，将已分配页划分为3种不同的迁移类型：**
- **不可移动页**：在内存中有固定位置，不能移动到其它地方（如：核心内核分配的大多数内存）
  
- **可回收页**：不能直接移动，但是可以删除重新生成（如：映射子文件的数据）
  
- **可移动页**：可以随意移动（如：用户空间应用程序）

```
#define MIGRATE_UNMOVABLE     0 //不可移动
#define MIGRATE_RECLAIMABLE   1 //可回收
#define MIGRATE_MOVABLE       2 //可移动
#define MIGRATE_RESERVE       3 //从可移动列表请求分配内存失败，紧急情况可以从预留处分配内存
#define MIGRATE_ISOLATE       4 /* can't allocate from here */
#define MIGRATE_TYPES         5
```

- **基本思想**：将**可移动页移动到新位置**，更新页表项，即可以分配较大的连续内存块

- **数据结构改进**：伙伴系统空闲列表`free_area->free_list`拆解出`MIGRATE_TYPES`个子列表

```
struct free_area {
    struct list_head    free_list[MIGRATE_TYPES];
    unsigned long        nr_free;
};
```

- 迁移类型的初始化：**页帧的迁移类型都是预先分配好的**，由页帧的**分配掩码**决定（`__GFP_MOVABLE`、`__GFP_RECLAIMABLE`）。如果分配内存时没有指定这些分配掩码，则该页帧是不可移动的。我们可以通过`/proc/pagetypeinfo`看到每个内存域的迁移类型对应的页帧情况：

```
# cat /proc/pagetypeinfo
Page block order: 9
Pages per block:  512

Free pages count per migrate type at order    0    1    2    3    4    5    6    7    8    9   10
......
Node   0, zone   Normal, type    Unmovable  281  480  209  129   35   12    3    2    0    1    0
Node   0, zone   Normal, type      Movable 7217 3995 2171  643  202   82   42   12    2    2 5946
Node   0, zone   Normal, type  Reclaimable   22    6    0   36   10    0    0    1    1    1    0
Node   0, zone   Normal, type   HighAtomic    0    0    0    0    0    0    0    0    0    0    0
Node   0, zone   Normal, type      Isolate    0    0    0    0    0    0    0    0    0    0    0
......
```

- 迁移类型的设置：`set_pageblock_migaratetype()`
- 迁移类型的读取：`get_pageblock_migaratetype()`
- 迁移备用列表`fallbacks`：如果内核无法满足针对某一给定迁移类型的分配请求，那么根据`fallbacks`指定从哪个迁移列表分配
  - 如：内核想要分配不可移动页时，如果对应空闲列表耗尽，从可回收页链表分配，还不行可以到可移动页链表、紧急分配链表分配

```
/*
 * This array describes the order lists are fallen back to when
 * the free lists for the desirable migrate type are depleted
 */
static int fallbacks[MIGRATE_TYPES][MIGRATE_TYPES-1] = {
    [MIGRATE_UNMOVABLE]   = { MIGRATE_RECLAIMABLE, MIGRATE_MOVABLE,   MIGRATE_RESERVE },
    [MIGRATE_RECLAIMABLE] = { MIGRATE_UNMOVABLE,   MIGRATE_MOVABLE,   MIGRATE_RESERVE },
    [MIGRATE_MOVABLE]     = { MIGRATE_RECLAIMABLE, MIGRATE_UNMOVABLE, MIGRATE_RESERVE },
    [MIGRATE_RESERVE]     = { MIGRATE_RESERVE,     MIGRATE_RESERVE,   MIGRATE_RESERVE }, /* Never used */
};
```

【注】内存子系统初始化期间，所有的页最初都标记为可移动的，而后转为不可移动的。这样避免启动期间内核分配的内存碎片散落在各处



**2. `ZONE_MOVABLE`**

- 防止碎片的另一种方式，是在内存域加入`ZONE_MOVABLE`。该机制需要由管理员显式激活

- `ZONE_MOVABLE`是虚拟内存域，不对应实际的页帧。根据体系的不同，可以置于`ZONE_NORMAL`或`ZONE_HIGHMEM`中

```
enum zone_type {
......
    ZONE_NORMAL,                //普通内存域，所有体系上都存在，
#ifdef CONFIG_HIGHMEM
    ZONE_HIGHMEM,               //高端内存
#endif
    ZONE_MOVABLE,               //伪内存域，防止物理内存碎片的机制用到
    MAX_NR_ZONES
};
```

- `ZONE_MOVABLE`内存数量：`find_zone_movable_pfns_for_nodes()`
- **基本思想**：可用的物理内存划分为两个内存域：可移动分配和不可移动分配。自动防止不可移动页的碎片引入可移动内存域
  - 个人理解：比如ZONE_NORMAL划分成两部分，可移动的部分都可以放在ZONE_MOVABLE中，不可移动的部分放在ZONE_MOVEABLE外。这样不可移动的碎片不会影响到内存可移动的部分，且管理的时候会比较方便



### 3.5.3 初始化内存域和结点数据结构

**1. 管理数据结构的创建**

![image-20221004175925284](C:\Users\THINKPAD\Desktop\learning\learning\image-20221004175925284.png)

- `early_node_map`：各结点页帧的分配情况
- `max_zone_pfns`：系统各个内存域页帧的边界
- `free_area_init_nodes()`：将各体系结构的结点和内存域通用化
  - 确定内存域边界：根据内存域的边界，计算各个内存域可使用的最低和最高的页帧编号，并分别记录到`arch_zone_lowest_possible_pfn`和`arch_zone_highest_possible_pfn`数组中
  - 遍历所有结点，调用`free_area_init_node()`建立其数据结构`pg_data_t`
  - 结点位图设置高端内存或普通内存标志

```
void __init free_area_init_nodes(unsigned long *max_zone_pfn)
{
    //对early_node_map进行排序，因为初始化代码假定它已经是排序的
    sort_node_map();
......
    //找到注册的最低内存域中可用编号最小的页帧，作为ZONE_DMA的下边界（当然，这里也有可能是ZONE_NORMAL）    
    arch_zone_lowest_possible_pfn[0] = find_min_pfn_with_active_regions();
    //记录ZONE_DMA的上边界
    arch_zone_highest_possible_pfn[0] = max_zone_pfn[0];
    
    //前一个内存域的最大页帧（前一个内存域的上边界），即下一个内存域的下边界
    for (i = 1; i < MAX_NR_ZONES; i++) {
        if (i == ZONE_MOVABLE)
            continue;
        arch_zone_lowest_possible_pfn[i] =
            arch_zone_highest_possible_pfn[i-1];
        arch_zone_highest_possible_pfn[i] =
            max(max_zone_pfn[i], arch_zone_lowest_possible_pfn[i]);
    }
    
    //MOVABLE内存域不占实际页帧
    arch_zone_lowest_possible_pfn[ZONE_MOVABLE] = 0;
    arch_zone_highest_possible_pfn[ZONE_MOVABLE] = 0;
    /* 找到ZONE_MOVABLE在各个节点的起始页帧编号 */
    memset(zone_movable_pfn, 0, sizeof(zone_movable_pfn));
    find_zone_movable_pfns_for_nodes(zone_movable_pfn);

    /* 输出有关内存域的信息 */
    printk("Zone PFN ranges:\n");
......

    //遍历所有结点，分别建立其数据结构pg_data_t
    for_each_online_node(nid) {
        pg_data_t *pgdat = NODE_DATA(nid);
        free_area_init_node(nid, pgdat, NULL, find_min_pfn_for_node(nid), NULL);

        /* 如果结点上有内存，结点位图设置N_HIGH_MEMORY标志 */
        if (pgdat->node_present_pages)
            node_set_state(nid, N_HIGH_MEMORY);
        //进一步检查低于ZONE_HIGHMEM的内存域中是否有内存，据此相应地设置N_NORMAL_MEMORY标志
        check_for_regular_memory(pgdat);
    }
}
```

- 其中，`free_area_init_node()`用于为每个结点建立`pg_data_t`数据结构
  - `calculate_node_totalpages()`：累计各个内存域的页数，计算结点中页的总数（包括空洞）
  - `alloc_node_mem_map()`：根据内存域的页数，为内存结点`pgdat`申请所有`struct page`实例所需要的物理内存。最后将物理内存的页指针记录到`pgdat->node_mem_map`中
  - `free_area_init_core()`：依次遍历结点的所有内存域，初始化各内存域的数据结构`pgdat->node_zones`

```
void __meminit free_area_init_node(int nid, struct pglist_data *pgdat,
        unsigned long *zones_size, unsigned long node_start_pfn,
        unsigned long *zholes_size)
{
    pgdat->node_id = nid;
    pgdat->node_start_pfn = node_start_pfn;
    calculate_node_totalpages(pgdat, zones_size, zholes_size);
    alloc_node_mem_map(pgdat);
    free_area_init_core(pgdat, zones_size, zholes_size);
}

static void __meminit calculate_node_totalpages(struct pglist_data *pgdat,
        unsigned long *zones_size, unsigned long *zholes_size)
{
......
    //结点中物理地址范围内的页帧总数，包括空洞部分
    for (i = 0; i < MAX_NR_ZONES; i++)
        totalpages += zone_spanned_pages_in_node(pgdat->node_id, i, zones_size);
    pgdat->node_spanned_pages = totalpages;

    //结点中真正可用的物理页面的数目，减去空洞
    realtotalpages = totalpages;
    for (i = 0; i < MAX_NR_ZONES; i++)
        realtotalpages -= zone_absent_pages_in_node(pgdat->node_id, i, zholes_size);
    pgdat->node_present_pages = realtotalpages;
}

static void __init_refok alloc_node_mem_map(struct pglist_data *pgdat)
{
    if (!pgdat->node_mem_map) {
......
        //根据结点的页帧总数，计算需要申请多少个struct page
        start = pgdat->node_start_pfn & ~(MAX_ORDER_NR_PAGES - 1);
        end = pgdat->node_start_pfn + pgdat->node_spanned_pages;
        end = ALIGN(end, MAX_ORDER_NR_PAGES);
        size =  (end - start) * sizeof(struct page);
        
        //申请size个struct page内存，记录到pgdat->node_mem_map数组中
        map = alloc_remap(pgdat->node_id, size);
        if (!map)
            map = alloc_bootmem_node(pgdat, size);
        pgdat->node_mem_map = map + (pgdat->node_start_pfn - start);
    }
    //如果是第0个结点，map还要记录到mem_map中
    if (pgdat == NODE_DATA(0)) {
        mem_map = NODE_DATA(0)->node_mem_map;
......
}

/*
 * Set up the zone data structures:
 *   - mark all pages reserved
 *   - mark all memory queues empty
 *   - clear the memory bitmaps
 */
static void __meminit free_area_init_core(struct pglist_data *pgdat,
        unsigned long *zones_size, unsigned long *zholes_size)
{
    enum zone_type j;
    int nid = pgdat->node_id;
    unsigned long zone_start_pfn = pgdat->node_start_pfn;
    int ret;

    pgdat_resize_init(pgdat);
    pgdat->nr_zones = 0;
    init_waitqueue_head(&pgdat->kswapd_wait);
    pgdat->kswapd_max_order = 0;
    
    for (j = 0; j < MAX_NR_ZONES; j++) {
        struct zone *zone = pgdat->node_zones + j;
......
        //遍历所有内存域，获取内存域的总长度（包含空洞）和真实长度（扣除空洞）
        size = zone_spanned_pages_in_node(nid, j, zones_size);
        realsize = size - zone_absent_pages_in_node(nid, j, zholes_size);

        //真实内存realsize需要扣除memmap_pages和dma_reserve的内存
......
        //nr_kernel_pages统计所有一致映射的页，nr_all_pages还包含高端内存页在内
        if (!is_highmem_idx(j))
            nr_kernel_pages += realsize;
        nr_all_pages += realsize;

        //spanned_pages记录内存域的总长度（包含空洞），present_pages记录内存域的真实长度（不含空洞）
        zone->spanned_pages = size;
        zone->present_pages = realsize;
        
        //以下初始化内存域zone数据结构
        zone->name = zone_names[j];
        zone->zone_pgdat = pgdat;
        //初始化内存域的per-CPU缓存
        zone_pcp_init(zone);
......
        //初始化zone->free_area列表，所有page实例设置为初始默认值：页的迁移类型为MIGRATE_MOVABLE
        ret = init_currently_empty_zone(zone, zone_start_pfn,
                        size, MEMMAP_EARLY);
        BUG_ON(ret);
        zone_start_pfn += size;
    }
}
```

- 初始化过程可以通过`dmesg`看到日志

```
[    0.020589] Initmem setup node 0 [mem 0x0000000000001000-0x000000207fffffff]
[    0.020591] On node 0 totalpages: 33465103
[    0.020592]   DMA zone: 64 pages used for memmap
[    0.020592]   DMA zone: 133 pages reserved
[    0.020593]   DMA zone: 3973 pages, LIFO batch:0
[    0.020646]   DMA32 zone: 6735 pages used for memmap
[    0.020648]   DMA32 zone: 430986 pages, LIFO batch:63
[    0.024810]   Normal zone: 516096 pages used for memmap
[    0.024812]   Normal zone: 33030144 pages, LIFO batch:63
[    0.025175] Initmem setup node 1 [mem 0x0000002080000000-0x000000407fffffff]
[    0.025177] On node 1 totalpages: 33554432
[    0.025178]   Normal zone: 524288 pages used for memmap
[    0.025178]   Normal zone: 33554432 pages, LIFO batch:63
```



### 3.5.4 分配器API

- **伙伴系统只能分配$size=2^{order}$的页**。更细粒度的分配，参见slab分配器（3.6节）

| 伙伴系统接口                    | 含义                                                         |
| ------------------------------- | ------------------------------------------------------------ |
| alloc_pages(mask, order)        | 分配$2^{order}$页，并返回一个`struct page`的实例，表示分配的内存块的起始页 |
| get_zeroed_page(mask)           | 分配一页，返回一个page实例，页对应的内存填充0                |
| __get_free_pages(mask, order)   | 类似上面两个函数，使用虚拟地址而不是page实例                 |
| get_dma_pages(gfp_mask, order)  | 获得适用于DMA的页                                            |
| free_pages(struct page*, order) | 将$2^{order}$页释放返回给内存管理子系统，page指向内存区的起始地址 |
| __free_page(addr, order)        | 类似free_pages，使用虚拟内存地址而不是page实例               |

【注】函数里面包含mask和order两个形参，具体参数有什么用呢，我们接着往下看



**1. 分配掩码`GFP_ZONEMASK`**

- 注：这里GFP代表获得空闲页（get free page）

![image-20221005182853756](C:\Users\THINKPAD\Desktop\learning\learning\image-20221005182853756.png)

- **内存域修饰符**（掩码最低4个比特）

```
#define __GFP_DMA    ((__force gfp_t)0x01u)
#define __GFP_HIGHMEM    ((__force gfp_t)0x02u)
#define __GFP_DMA32    ((__force gfp_t)0x04u)
```

- `GFP_DMA`、`GFP_HIGHMEM`、`GFP_DMA32`：分配适用于DMA、HIGHMEM、DMA32内存域的内存时，要扫描那些内存域完成分配

![image-20221005211259221](C:\Users\THINKPAD\Desktop\learning\learning\image-20221005211259221.png)



- 其它标志：影响分配器的行为，比如修改查找空闲内存的积极程度

```
#define __GFP_WAIT    ((__force gfp_t)0x10u)    /* Can wait and reschedule? */
#define __GFP_HIGH    ((__force gfp_t)0x20u)    /* Should access emergency pools? */
#define __GFP_IO    ((__force gfp_t)0x40u)    /* Can start physical IO? */
#define __GFP_FS    ((__force gfp_t)0x80u)    /* Can call down to low-level FS? */
#define __GFP_COLD    ((__force gfp_t)0x100u)    /* Cache-cold page required */
#define __GFP_NOWARN    ((__force gfp_t)0x200u)    /* Suppress page allocation failure warning */
#define __GFP_REPEAT    ((__force gfp_t)0x400u)    /* Retry the allocation.  Might fail */
#define __GFP_NOFAIL    ((__force gfp_t)0x800u)    /* Retry for ever.  Cannot fail */
#define __GFP_NORETRY    ((__force gfp_t)0x1000u)/* Do not retry.  Might fail */
#define __GFP_COMP    ((__force gfp_t)0x4000u)/* Add compound page metadata */
#define __GFP_ZERO    ((__force gfp_t)0x8000u)/* Return zeroed page on success */
#define __GFP_NOMEMALLOC ((__force gfp_t)0x10000u) /* Don't use emergency reserves */
#define __GFP_HARDWALL   ((__force gfp_t)0x20000u) /* Enforce hardwall cpuset memory allocs */
#define __GFP_THISNODE    ((__force gfp_t)0x40000u)/* No fallback, no policies */
#define __GFP_RECLAIMABLE ((__force gfp_t)0x80000u) /* Page is reclaimable */
#define __GFP_MOVABLE    ((__force gfp_t)0x100000u)  /* Page is movable */
```

- 修饰符组合

| 宏                     | 修饰符组合                                                   | 语义                                         |
| ---------------------- | ------------------------------------------------------------ | -------------------------------------------- |
| `GFP_ATOMIC`           | `__GFP_HIGH`                                                 | 原子分配，任何情况下都不能中断               |
| `GFP_NOIO`             | `__GFP_WAIT`                                                 | 分配期间禁止IO操作，但可以中断               |
| `GFP_NOFS`             | `__GFP_WAIT|__GFP_IO`                                        | 分配期间禁止访问VFS层，但允许中断和IO操作    |
| `GFP_KERNEL`           | `__GFP_WAIT|__GFP_IO|__GFP_FS`                               | 内核空间分配默认设置                         |
| `GFP_USER`             | `__GFP_WAIT|__GFP_IO|__GFP_FS|`<br/>`__GFP_HARDWALL`         | 用户空间分配默认设置                         |
| `GFP_HIGHUSER`         | `__GFP_WAIT|__GFP_IO|__GFP_FS|`<br>`__GFP_HARDWALL|__GFP_HIGHMEM` | 用于用户空间，允许分配无法直接映射的高端内存 |
| `GFP_HIGHUSER_MOVABLE` | `__GFP_WAIT|__GFP_IO|__GFP_FS|`<br>`__GFP_HARDWALL|__GFP_HIGHMEM|__GFP_MOVABLE` | 类似GFP_HIGHUSER，分配将从ZONE_MOVABLE进行   |
| `GFP_DMA`              | `__GFP_DMA`                                                  | 分配DMA的内存                                |
| `GFP_DMA32`            | `__GFP_DMA32`                                                | 分配DMA32的内存                              |



**2. 伙伴系统各个分配函数的关系**

- 伙伴系统的内存分配和释放接口，皆可追溯到`alloc_pages_node()`和`__free_pages()`

![image-20221005221757375](C:\Users\THINKPAD\Desktop\learning\learning\image-20221005221757375.png)

![image-20221005221818683](C:\Users\THINKPAD\Desktop\learning\learning\image-20221005221818683.png)



### 3.5.5 分配页

- 伙伴系统的内存分配都追溯到`alloc_pages_node()`。其中`__alloc_pages()`是核心函数

**1. 分配标志和辅助函数**

- **分配标志`alloc_flags`**
  - `ALLOC_WMARK_HIGH`：空闲页大于`zone->page_high`，才能分配对象
  - `ALLOC_WMARK_LOW`：空闲页大于`zone->page_low`，才能分配对象
  - `ALLOC_WMARK_MIN`：空闲页大于`zone->page_min`，才能分配对象
  - `ALLOC_HIGH`：伙伴系统在急需内存时，放宽分配规则：允许水位最小值降低到当前值的一半
  - `ALLOC_HARDER`：伙伴系统在急需内存时，更加放宽分配规则：允许水位最小值降低到当前值的四分之一
  - `ALLOC_CPUSET`：内存只能从当前进程允许运行的CPU相关的内存结点分配


```
#define ALLOC_NO_WATERMARKS    0x01 /* don't check watermarks at all */
#define ALLOC_WMARK_MIN        0x02 /* use pages_min watermark */
#define ALLOC_WMARK_LOW        0x04 /* use pages_low watermark */
#define ALLOC_WMARK_HIGH       0x08 /* use pages_high watermark */
#define ALLOC_HARDER           0x10 /* try to alloc harder */
#define ALLOC_HIGH             0x20 /* __GFP_HIGH set */
#define ALLOC_CPUSET           0x40 /* check for correct cpuset */
```

- **`zone_watermark_ok()`：伙伴系统辅助函数，检查是否能从给定的内存域分配内存**

```
int zone_watermark_ok(struct zone *z, int order, unsigned long mark,
              int classzone_idx, int alloc_flags)
{
    /* free_pages可能变为负数，没有关系 */
    long min = mark;
    long free_pages = zone_page_state(z, NR_FREE_PAGES) - (1 << order) + 1;
    int o;

    //如果设置了ALLOC_HIGH和ALLOC_HARDER，水位的最小值降低，放宽分配限制
    if (alloc_flags & ALLOC_HIGH)
        min -= min / 2;
    if (alloc_flags & ALLOC_HARDER)
        min -= min / 4;

    //内存域中，除了预留内存外，如果空闲内存比最小值还小，不允许分配内存
    if (free_pages <= min + z->lowmem_reserve[classzone_idx])
        return 0;
    for (o = 0; o < order; o++) {
        //判断能否分配第o阶的内存。判断前需要扣除小于o阶的页
        free_pages -= z->free_area[o].nr_free << o;
        //每升高一阶，所需空闲页的最小值减半
        min >>= 1;
        //如果遍历所有阶的空闲内存比最小值还小，则不允许分配内存
        if (free_pages <= min)
            return 0;
    }
    return 1;
}
```

【注】说实话算法没看懂，比如这里要申请$2^3$的内存(order=3)，正常应该是找3~MAX_ORDER的空闲页链表里面，链表非空表示允许分配内存了。这里凭什么比较order=0,1,2的空闲页和最小值min可以得知是否允许分配内存╮(╯▽╰)╭。后面去翻了一下4.14的内核源码，发现有比较大的改动：

```
    /* For a high-order request, check at least one suitable page is free */
    for (o = order; o < MAX_ORDER; o++) {
        struct free_area *area = &z->free_area[o];
        int mt;

        if (!area->nr_free)
            continue;

        for (mt = 0; mt < MIGRATE_PCPTYPES; mt++) {
            if (!list_empty(&area->free_list[mt]))
                return true;
        }
......
    }
    return false;
```



- **`get_page_from_freelist()`：伙伴系统辅助函数，遍历所有备用列表的内存域，尝试找一个适当的空闲内存块**
  - 使用`zone_watermark_ok()`检查当前内存域是否能够分配空闲页
  - 如果找到了，使用`buffered_rmqueue()`分配所需数目的页，返回给调用者
  - 如果没找到，返回NULL

```
static struct page *
get_page_from_freelist(gfp_t gfp_mask, unsigned int order,
        struct zonelist *zonelist, int alloc_flags)
{
......
    //遍历所有备用列表的内存域，找到一个适当的空闲内存块
zonelist_scan:
    z = zonelist->zones;

    do {
......
        zone = *z;
        //如果检查的内存域不属于当前进程允许运行的CPU（即进程不能使用这个内存域），则尝试下一个域
        if ((alloc_flags & ALLOC_CPUSET) &&
            !cpuset_zone_allowed_softwall(zone, gfp_mask))
                goto try_next_zone;

        //根据alloc_flags调整水位最小值
        if (!(alloc_flags & ALLOC_NO_WATERMARKS)) {
            unsigned long mark;
            if (alloc_flags & ALLOC_WMARK_MIN)
                mark = zone->pages_min;
            else if (alloc_flags & ALLOC_WMARK_LOW)
                mark = zone->pages_low;
            else
                mark = zone->pages_high;
            //使用zone_watermark_ok检查当前内存域是否能够分配空闲页
            if (!zone_watermark_ok(zone, order, mark, classzone_idx, alloc_flags)) {
                if (!zone_reclaim_mode || !zone_reclaim(zone, gfp_mask, order))
                    goto this_zone_full;    //这里等价于continue，重新循环
            }
        }

        //分配所需数目的页，返回给调用者
        page = buffered_rmqueue(zonelist, zone, order, gfp_mask);
        if (page)
            break;
this_zone_full:
......
try_next_zone:
......
    } while (*(++z) != NULL);

......
    return page;
}
```



**2. 分配控制`__alloc_pages()`**

- 内存域空闲页充足，调用一次`get_page_from_freelist()`可以返回所需数目的页
- 内存不足，唤醒`kswapd`守护进程回收页面。内核修改分配标志，尝试重新通过`get_page_from_freelist()`获取页
- 进程设置了PF_MEMALLOC（紧急分配内存），或者TIF_MEMDIE（进程被OOM killer选中），可以忽略水位，重新获取页
- 内核调度，等待页面回收完成（这里很慢）。如果释放了一些物理内存，尝试重新获取页
- 内核允许使用可能影响VFS的操作（`__GFP_FS`）且允许重试分配内存（`!__GFP_NORETRY`），可调用OOM Killer腾出较多的空闲页，然后重新尝试分配内存
- 如果分配的内存较小（order <= PAGE_ALLOC_COSTLY_ORDER，8页），或内核设置了`__GFP_REPEAT`、`__GFP_NOFAIL`标志，则无限循环重试获取页
- 分配页成功返回页指针；失败返回NULL

```
/*
 * This is the 'heart' of the zoned buddy allocator.
 */
struct page * fastcall
__alloc_pages(gfp_t gfp_mask, unsigned int order,
        struct zonelist *zonelist)
{
......
//重新获取页入口
restart:
......
    //1. 最简单的场景，尝试遍历所有内存域获取空闲页返回。alloc_flags = ALLOC_WMARK_LOW|ALLOC_CPUSET
    page = get_page_from_freelist(gfp_mask|__GFP_HARDWALL, order,
                zonelist, ALLOC_WMARK_LOW|ALLOC_CPUSET);
    if (page)
        goto got_pg;

......
    //2. 内存不足，唤醒kswapd守护进程，回收页面（异步）
    for (z = zonelist->zones; *z; z++)
        wakeup_kswapd(*z, order);

    //修改分配标志，水位降低至min，再次尝试遍历内存域获取空闲页
    alloc_flags = ALLOC_WMARK_MIN;
    if ((unlikely(rt_task(p)) && !in_interrupt()) || !wait)
        alloc_flags |= ALLOC_HARDER;
    if (gfp_mask & __GFP_HIGH)
        alloc_flags |= ALLOC_HIGH;
    if (wait)
        alloc_flags |= ALLOC_CPUSET;

    page = get_page_from_freelist(gfp_mask, order, zonelist, alloc_flags);
    if (page)
        goto got_pg;

//低速路径入口
rebalance:
    //3. 进程设置了PF_MEMALLOC（紧急分配内存），或者TIF_MEMDIE（进程被OOM killer选中），可以忽略水位，重新获取页
    if (((p->flags & PF_MEMALLOC) || unlikely(test_thread_flag(TIF_MEMDIE)))
            && !in_interrupt()) {
        //如果设置了__GFP_NOMEMALLOC，禁止使用紧急分配链表，分配失败
        if (!(gfp_mask & __GFP_NOMEMALLOC)) {
nofail_alloc:
            /* 再次遍历zonelist，忽略watermark */
            page = get_page_from_freelist(gfp_mask, order, zonelist, ALLOC_NO_WATERMARKS);
            if (page)
                goto got_pg;
            //设置了一直重试标志__GFP_NOFAIL，则无限循环
            if (gfp_mask & __GFP_NOFAIL) {
                //等待块设备层队列释放
                congestion_wait(WRITE, HZ/50);
                goto nofail_alloc;
            }
        }
        goto nopage;
    }

    //如果设置了__GFP_WAIT，表示分配操作耗时长，有可能使进程睡眠；如果没设置，则返回page=NULL
    if (!wait)
        goto nopage;
    cond_resched();

......
    //我们现在进入同步回收状态
    p->flags |= PF_MEMALLOC;
    //选择最近不十分活跃的页，将其写到交换区，在物理内存中腾出空间
    did_some_progress = try_to_free_pages(zonelist->zones, order, gfp_mask);
    p->flags &= ~PF_MEMALLOC;
    cond_resched();
......
    //4. 如果try_to_free_pages释放了一些物理内存，尝试重新获取空闲页
    if (likely(did_some_progress)) {
        page = get_page_from_freelist(gfp_mask, order,
                        zonelist, alloc_flags);
        if (page)
            goto got_pg;
    
    //5. 内核允许使用可能影响VFS的操作（__GFP_FS）且允许重试（!__GFP_NORETRY），可调用OOM Killer腾出较多的空闲页，然后重新尝试分配内存
    } else if ((gfp_mask & __GFP_FS) && !(gfp_mask & __GFP_NORETRY)) {
......
        //这里如果阶数较大（申请的连续内存页很大，通常是8页以上），忽略这个机制
        if (order > PAGE_ALLOC_COSTLY_ORDER) {
            clear_zonelist_oom(zonelist);
            goto nopage;
        }
        out_of_memory(zonelist, gfp_mask, order);
        goto restart;
    }

    //6. 如果分配长度小于8页，或内核设置了__GFP_REPEAT、__GFP_NOFAIL标志，则无限循环
    do_retry = 0;
    if (!(gfp_mask & __GFP_NORETRY)) {
        if ((order <= PAGE_ALLOC_COSTLY_ORDER) || (gfp_mask & __GFP_REPEAT))
            do_retry = 1;
        if (gfp_mask & __GFP_NOFAIL)
            do_retry = 1;
    }
    if (do_retry) {
        //等待块设备层队列释放
        congestion_wait(WRITE, HZ/50);
        goto rebalance;
    }

nopage:
    if (!(gfp_mask & __GFP_NOWARN) && printk_ratelimit()) {
        printk(KERN_WARNING "%s: page allocation failure."
            " order:%d, mode:0x%x\n",
            p->comm, order, gfp_mask);
        dump_stack();
        show_mem();
    }
got_pg:
    return page;
}
```



**3. 分配空闲页**

- **`buffered_rmqueue()`：寻找所需数目的页，从伙伴系统删除，最后返回给调用者**。分单页和多页两种情况

![image-20221007012613457](C:\Users\THINKPAD\Desktop\learning\learning\image-20221007012613457.png)

- **分配单页**：这里内核进行了优化，不是直接从伙伴系统中获取页，而是**从L2缓存中获取冷热页分配**。至于是使用冷页还是热页、迁移类型如何由`gfp_flags`决定。过程：
  - 如果缓存中没有足够的页，从伙伴系统获取页并填充
  - 遍历缓存的所有页，寻找对应迁移类型的页
  - 缓存列表删除一页，返回页指针
  - 预处理分配的页，初始化标志
- **分配多页**：
  - **调用`__rmqueue()`从伙伴系统中获取多个页**（可能有重排内存区等行为），返回页指针
  - 预处理分配的页，初始化标志

```C++
/*
 * Really, prep_compound_page() should be called from __rmqueue_bulk().  But
 * we cheat by calling it from here, in the order > 0 path.  Saves a branch
 * or two.
 */
static struct page *buffered_rmqueue(struct zonelist *zonelist,
            struct zone *zone, int order, gfp_t gfp_flags)
{
    unsigned long flags;
    struct page *page;
    //这里取两次!是为了将返回结果转为0或者1
    int cold = !!(gfp_flags & __GFP_COLD);
    int cpu;
    int migratetype = allocflags_to_migratetype(gfp_flags);

again:
    cpu  = get_cpu();
    //如果仅请求一页，该页取自per-CPU缓存优化（L2缓存），而不是伙伴系统
    if (likely(order == 0)) {
        struct per_cpu_pages *pcp;

        //对当前处理器选择了适当的冷页列表，调用rmqueue_bulk重新填充缓存
        pcp = &zone_pcp(zone, cpu)->pcp[cold];
        local_irq_save(flags);
        if (!pcp->count) {
            //从伙伴系统移除页，然后添加到缓存中
            pcp->count = rmqueue_bulk(zone, 0,
                    pcp->batch, &pcp->list, migratetype);
            if (unlikely(!pcp->count))
                goto failed;
        }

        //遍历per-CPU缓存的所有页，寻找有适当迁移类型的页
        list_for_each_entry(page, &pcp->list, lru)
            if (page_private(page) == migratetype)
                break;

        /* 如无法找到适当的页，向pcp列表添加一些符合迁移条件的页 */
        if (unlikely(&page->lru == &pcp->list)) {
            pcp->count += rmqueue_bulk(zone, 0,
                    pcp->batch, &pcp->list, migratetype);
            page = list_entry(pcp->list.next, struct page, lru);
        }
        
        //per-CPU缓存列表移除一页
        list_del(&page->lru);
        pcp->count--;
        
    } else {
        //如果要分配多个页，内核调用__rmqueue从伙伴列表中选择适当的内存块。请注意这里需加锁
        spin_lock_irqsave(&zone->lock, flags);
        page = __rmqueue(zone, order, migratetype);
        spin_unlock(&zone->lock);
        //注意：内存域没有足够的连续空闲页，也会报错
        if (!page)
            goto failed;
    }
......
    //预处理分配的页，以便内核能够处理这些页。出现问题从头分配
    if (prep_new_page(page, order, gfp_flags))
        goto again;
    return page;

failed:
......
    return NULL;
}

//预处理分配的页，以便内核能够处理这些页
static int prep_new_page(struct page *page, int order, gfp_t gfp_flags)
{
......
    //新页设置以下默认标志
    page->flags &= ~(1 << PG_uptodate | 1 << PG_error | 1 << PG_readahead |
            1 << PG_referenced | 1 << PG_arch_1 |
            1 << PG_owner_priv_1 | 1 << PG_mappedtodisk);
......
    //如果设置了__GFP_ZERO，需要将页填充字节0
    if (gfp_flags & __GFP_ZERO)
        prep_zero_page(page, order, gfp_flags);

    //如果设置了__GFP_COMP，将页组织为复合页（可用于hugepage）
    if (order && (gfp_flags & __GFP_COMP))
        prep_compound_page(page, order);

    return 0;
}
```

- **分配多个页时，伙伴系统的核心操作位于`__rmqueue()`**。过程如下：
  - `__rmqueue_smallest（）`：当前迁移类型`migratetype`由`gfp_flags`得到，**先尝试从当前迁移类型**所在的`free_area->free_list`中获取并分配空闲页
  - `__rmqueue_fallback（）`：如果当前迁移类型无法分配空闲页**，再尝试根据`fallbacks`迁移备用列表**，找备用的迁移类型所在的`free_list`中获取并分配空闲页


```
static struct page *__rmqueue(struct zone *zone, unsigned int order,
                        int migratetype)
{
    struct page *page;
    //尝试用当前迁移类型migratetype所在的free_list，分配空闲页
    page = __rmqueue_smallest(zone, order, migratetype);

    if (unlikely(!page))
        //如果当前迁移类型无法分配空闲页，从备用迁移类型（从fallbacks找）分配空闲页
        page = __rmqueue_fallback(zone, order, migratetype);

    return page;
}
```

- **`__rmqueue_smallest（）`：从当前迁移类型所在的`free_list`分配空闲页**
  - 从`order`阶开始找空闲块。如果`free_area[order]->free_list`含空闲页，表示找到
    - 伙伴系统`free_list`移出空闲页，清除标志`PG_BUDDY`

  - 如果`order`阶`free_list`没有找到空闲页，继续往`order+1`阶开始找，直到`order=MAX_ORDER`
    - 伙伴系统`free_list`移出空闲页，清除标志`PG_BUDDY`
    - 按伙伴系统原理，逐层分裂成更小块，更新伙伴系统各阶`free_list`（看例子）


```
/*
 * Go through the free lists for the given migratetype and remove
 * the smallest available page from the freelists
 */
static struct page *__rmqueue_smallest(struct zone *zone, unsigned int order,
                        int migratetype)
{
    unsigned int current_order;
    struct free_area * area;
    struct page *page;

    //从order阶free_area开始找空闲块。如果order阶free_area没找到，就找order+1阶，然后分裂进行分配
    for (current_order = order; current_order < MAX_ORDER; ++current_order) {
        //如果列表非空，表明当前order阶free_list有空闲块
        //如果列表为空，找order+1阶
        area = &(zone->free_area[current_order]);
        if (list_empty(&area->free_list[migratetype]))
            continue;

        //返回空闲页，free_list移除这个空闲页
        page = list_entry(area->free_list[migratetype].next,
                            struct page, lru);
        list_del(&page->lru);
        //空闲页标志删除PG_BUDDY位
        rmv_page_order(page);
        area->nr_free--;
        //更新当前内存域的统计量
        __mod_zone_page_state(zone, NR_FREE_PAGES, - (1UL << order));
        //如果从较高的order分配了空闲页，则需要按照伙伴系统原理分裂成更小的块
        expand(zone, page, order, current_order, area, migratetype);
        return page;
    }

    return NULL;
}

//如果从较高的order分配了空闲页，则需要按照伙伴系统原理分裂成更小的块
static inline void expand(struct zone *zone, struct page *page,
    int low, int high, struct free_area *area,
    int migratetype)
{
    unsigned long size = 1 << high;

    while (high > low) {
        //空闲块大小分为两半，前一半用于返回，后一半加入到下一级的free_list中
        area--;
        high--;
        size >>= 1;
        list_add(&page[size].lru, &area->free_list[migratetype]);
        area->nr_free++;
        //后一半空闲页加入到free_list后，需要设置PG_BUDDY位，表示加入到伙伴系统里
        set_page_order(&page[size], high);
    }
}
```

- 【例】书中例子，伙伴系统中，分配一个8页内存块*（这里图画的有问题，是前一半拆开）*

![image-20221007181330301](C:\Users\THINKPAD\Desktop\learning\learning\image-20221007181330301.png)

【过程】

- 找`order = 3`的`free_list`。此时`free_area[3]->free_list`为空，也就是说没有空闲块，继续找
- 找`order = 4`的`free_list`。此时`free_area[4]->free_list`为空，也就是说没有空闲块，继续找
- 找`order = 5`的`free_list`。此时`free_area[5]->free_list`非空，取出5阶空闲块
- 5阶空闲块（size=32页）拆成两个部分，后一半加入到`free_area[4]->free_list`中，前一半4阶空闲块继续拆
- 4阶空闲块（size=16页）拆成两个部分，后一半加入到`free_area[3]->free_list`中，前一半3阶空闲块的page指针作为结果返回



- **`__rmqueue_fallback()`：尝试根据`fallbacks`备用迁移类型列表，找备用的迁移类型所在的`free_list`中获取并分配空闲页**
  - 遍历备用迁移类型列表，找尽可能大的空闲块（尽可能大是为了防止引入不同迁移类型的碎片）
  - 如果找到的空闲块较大（由pageblock_order宏决定），或者分配可回收类型的内存页（MIGRATE_RECLAIMABLE），将整个内存块改变迁移类型，转到当前分配类型对应的迁移列表
  - 伙伴系统移出空闲块，按伙伴系统进行分裂。如果迁移类型变为当前分配类型，则剩余块加入到当前迁移类型的`free_list`中；如果迁移类型未改变，则加到原迁移类型的`free_list`中
  - 最后的手段：从MIGRATE_RESERVE列表分配内存


```
//pageblock_order宏定义什么是较大的内存块，通常由体系结构决定。如果体系结构支持巨型页，IA-32体系为10；如果不支持，定义为第二高的分配阶10
#ifdef CONFIG_HUGETLB_PAGE
#define pageblock_order        HUGETLB_PAGE_ORDER
#else /* CONFIG_HUGETLB_PAGE */
#define pageblock_order        (MAX_ORDER-1)
#endif /* CONFIG_HUGETLB_PAGE */

//备用迁移类型列表，比如MOVABLE找不到空闲页，继续从RECLAIMABLE开始找
static int fallbacks[MIGRATE_TYPES][MIGRATE_TYPES-1] = {
    [MIGRATE_UNMOVABLE]   = { MIGRATE_RECLAIMABLE, MIGRATE_MOVABLE,   MIGRATE_RESERVE },
    [MIGRATE_RECLAIMABLE] = { MIGRATE_UNMOVABLE,   MIGRATE_MOVABLE,   MIGRATE_RESERVE },
    [MIGRATE_MOVABLE]     = { MIGRATE_RECLAIMABLE, MIGRATE_UNMOVABLE, MIGRATE_RESERVE },
    [MIGRATE_RESERVE]     = { MIGRATE_RESERVE,     MIGRATE_RESERVE,   MIGRATE_RESERVE }, /* Never used */
};

/* Remove an element from the buddy allocator from the fallback list */
static struct page *__rmqueue_fallback(struct zone *zone, int order,
                        int start_migratetype)
{
    struct free_area * area;
    int current_order;
    struct page *page;
    int migratetype, i;

    /* 从其他迁移类型列表中，找到最大可能的内存块。这里从大到小遍历的目的是防止各个迁移类型的内存块混杂，减少碎片 */
    for (current_order = MAX_ORDER-1; current_order >= order; --current_order) {
        //遍历备用迁移类型列表
        for (i = 0; i < MIGRATE_TYPES - 1; i++) {
            migratetype = fallbacks[start_migratetype][i];

            /* 遇到MIGRATE_RESERVE先跳过 */
            if (migratetype == MIGRATE_RESERVE)
                continue;

            area = &(zone->free_area[current_order]);
            if (list_empty(&area->free_list[migratetype]))
                continue;

            //从别的迁移列表找到了尽可能大的空闲块
            page = list_entry(area->free_list[migratetype].next,
                    struct page, lru);
            area->nr_free--;

            //如果找到的空闲块比较大，或者当前分配的是可回收类型的空闲块
            if (unlikely(current_order >= (pageblock_order >> 1)) ||
                    start_migratetype == MIGRATE_RECLAIMABLE) {
                unsigned long pages;
                
                //把找到的空闲块移到当前分配类型的迁移列表中，并修改迁移类型
                pages = move_freepages_block(zone, page, start_migratetype);

                /* 如果大内存块超过一半是空闲的，则主张对整个大内存块的所有权 */
                if (pages >= (1 << (pageblock_order-1)))
                    set_pageblock_migratetype(page, start_migratetype);

                migratetype = start_migratetype;
            }

            //空闲列表移除页，更新内存域统计量
            list_del(&page->lru);
            rmv_page_order(page);
            __mod_zone_page_state(zone, NR_FREE_PAGES, -(1UL << order));

            if (current_order == pageblock_order)
                set_pageblock_migratetype(page, start_migratetype);

            //使用expand分裂出合适大小的部分返回，未用部分还给伙伴系统
            expand(zone, page, order, current_order, area, migratetype);
            return page;
        }
    }

    //最后的手段：从MIGRATE_RESERVE列表分配内存
    return __rmqueue_smallest(zone, order, MIGRATE_RESERVE);
}
```



### 3.5.6 释放页

- **核心函数：`__free_page()`，分为释放单页和释放多页场景**

![image-20221007170051668](C:\Users\THINKPAD\Desktop\learning\learning\image-20221007170051668.png)

- **释放单页`free_hot_cold_page()`：页回收到L2缓存中，而不是直接还给伙伴系统**
  - 如果缓存中的页比较多，再还一部分给伙伴系统

```C++
/*
 * Free a 0-order page
 */
static void fastcall free_hot_cold_page(struct page *page, int cold)
{
......
    //页添加到缓存的热页列表中，将page->private设置为页的迁移类型
    pcp = &zone_pcp(zone, get_cpu())->pcp[cold];
    list_add(&page->lru, &pcp->list);
    set_page_private(page, get_pageblock_migratetype(page));
    pcp->count++;
    //惰性合并：如果缓存中页的数目超出了pcp->high，将pcp->batch数目的内存页还给伙伴系统
    if (pcp->count >= pcp->high) {
        //将页还给伙伴系统
        free_pages_bulk(zone, pcp->batch, &pcp->list, 0);
        pcp->count -= pcp->batch;
    }
......
}
```

- **释放多页`__free_one_page()`：先找page伙伴buddy，如果伙伴也是空闲的，逐层合并**
  - 伙伴的地址：buddy_idx = page_idx ^ (1 << order)
  - 合并后地址：combined_idx = page_idx & ~(1 << order)
  - 伙伴是空闲的：页在伙伴系统中设置了PG_buddy

```
static inline void __free_one_page(struct page *page,
        struct zone *zone, unsigned int order)
{
......
    //尝试释放page的合并流程，可能合并多次
    while (order < MAX_ORDER-1) {
        unsigned long combined_idx;
        struct page *buddy;

        //找到页的伙伴buddy
        buddy = __page_find_buddy(page, page_idx, order);
        //如果伙伴不是空闲的，不允许合并
        if (!page_is_buddy(page, buddy, order))
            break;        /* Move the buddy up one level. */

        //伙伴也是空闲的，将伙伴系统空闲列表的buddy删除掉
        list_del(&buddy->lru);
        zone->free_area[order].nr_free--;
        //清除buddy页的PG_BUDDY标志
        rmv_page_order(buddy);
        //更新page
        combined_idx = __find_combined_index(page_idx, order);
        page = page + (combined_idx - page_idx);
        page_idx = combined_idx;
        order++;
    }
    //page加入到伙伴系统中
    set_page_order(page, order);
    list_add(&page->lru, &zone->free_area[order].free_list[migratetype]);
    zone->free_area[order].nr_free++;
}
```

【例】书中例子，将第10页还给伙伴系统

![image-20221007181204281](C:\Users\THINKPAD\Desktop\learning\learning\image-20221007181204281.png)

【过程】

| order | page_idx | buddy_idx | combined_idx | 说明                                       |
| ----- | -------- | --------- | ------------ | ------------------------------------------ |
| 0     | 10       | 10^1=11   | 10&~1=10     | 找到页10的伙伴11，合并后页首地址10         |
| 1     | 10       | 10^2=8    | 10&~2=8      | 找到页[10,11]的伙伴[8,9]，合并后页首地址8  |
| 2     | 8        | 8^4=12    | 8&~4=8       | 找到页[8,11]的伙伴[12,15]，合并后页首地址8 |
| 3     | 8        | 8^8=0     | 8&~8=0       | 找到页[8,15]的伙伴[0,7]，合并后页首地址0   |



### 3.5.7 内核中对不连续页的分配

![image-20221008000341177](C:\Users\THINKPAD\Desktop\learning\learning\image-20221008000341177.png)

- **目的**：在高端内存域中，内核分配虚拟内存中连续、但物理内存中不连续的内存区（比如动态加载模块时，会出现内存碎片）

- **数据结构**：每个用`vmalloc`分配的子区域，都对应一个`struct vm_struct`实例。该结构组织为一个链表。（**在高版本内核中，使用==红黑树==优化**）

```c++
struct vm_struct {
    /* keep next,addr,size together to speedup lookups */
    struct vm_struct    *next;       //指向下一个vm_struct
    void                *addr;       //起始地址
    unsigned long       size;        //长度（字节）
    unsigned long       flags;       //指定内存区类型，
    struct page         **pages;     //物理页的page实例
    unsigned int        nr_pages;    //pages数组项数目，即涉及的内存页数目
    unsigned long       phys_addr;   //仅当用ioremap映射了物理地址描述的物理内存区域时才需要
};
```

- **管理函数**：寻找空闲内存、分配内存、释放内存
- **`get_vm_area_node()`：在vmalloc区域寻找空闲内存，用于分配**
  - 各vmalloc间要插入一个保护页（1页）
  - 遍历vmlist，找到一个合适的位置，初始化新的链表元素，并添加到vmlist全局链表中
    - 
  - 如果没有找到合适的内存，返回NULL

```
//全局变量，记录虚拟内存区链表。表头为vmlist
struct vm_struct *vmlist;

static struct vm_struct *__get_vm_area_node(unsigned long size, unsigned long flags,
					    unsigned long start, unsigned long end,
					    int node, gfp_t gfp_mask)
{
......
	//对齐页大小
	size = PAGE_ALIGN(size);
......
	//总是分配一个保护页
	size += PAGE_SIZE;

	write_lock(&vmlist_lock);
	//遍历vmlist，找到一个合适的位置
	for (p = &vmlist; (tmp = *p) != NULL ;p = &tmp->next) {
		if ((unsigned long)tmp->addr < addr) {
			if((unsigned long)tmp->addr + tmp->size >= addr)
				addr = ALIGN(tmp->size + 
					     (unsigned long)tmp->addr, align);
			continue;
		}
		if ((size + addr) < addr)
			goto out;
		if (size + addr <= (unsigned long)tmp->addr)
			goto found;
		addr = ALIGN(tmp->size + (unsigned long)tmp->addr, align);
		if (addr > end - size)
			goto out;
	}

found:
	//初始化新的链表元素，并添加到vmlist全局链表中
	area->next = *p;
	*p = area;

	area->flags = flags;
	area->addr = (void *)addr;
	area->size = size;
	area->pages = NULL;
	area->nr_pages = 0;
	area->phys_addr = 0;
	write_unlock(&vmlist_lock);

	return area;

out:
	write_unlock(&vmlist_lock);
......
	return NULL;
}
```



- **`vmalloc()`：分配内存区**
  - 在vmalloc地址空间中找到一个适当的区域
  - 从伙伴系统上，逐页找物理内存分配，分配失败返回NULL
  - 最后将这些物理页连续地映射到vmalloc区域中，更新页表并刷新CPU高速缓存

```
//分配内存vmalloc()，最终会调用到这一函数
static void *__vmalloc_node(unsigned long size, gfp_t gfp_mask, pgprot_t prot,
			    int node)
{
......
	//在vmalloc地址空间找到合适区域
	area = get_vm_area_node(size, VM_ALLOC, node, gfp_mask);
	if (!area)
		return NULL;

	return __vmalloc_area_node(area, gfp_mask, prot, node);
}


void *__vmalloc_area_node(struct vm_struct *area, gfp_t gfp_mask,
				pgprot_t prot, int node)
{
......
	//如果显式指定了分配页帧的结点，则内核调用alloc_pages_node；否则使用alloc_pages从当前结点分配页帧
	//这里是一页一页地在伙伴系统上分配内存
	for (i = 0; i < area->nr_pages; i++) {
		if (node < 0)
			area->pages[i] = alloc_page(gfp_mask);
		else
			area->pages[i] = alloc_pages_node(node, gfp_mask, 0);
	}
......
	//将分散的物理内存页连续映射到虚拟的vmalloc区域
	if (map_vm_area(area, prot, &pages))
		goto fail;
	//分配成功，返回vmalloc区域的地址
	return area->addr;

fail:
	vfree(area->addr);
	return NULL;
}

//将分散的物理内存页连续映射到虚拟的vmalloc区域
int map_vm_area(struct vm_struct *area, pgprot_t prot, struct page ***pages)
{
......
	pgd = pgd_offset_k(addr);
	//遍历分配的物理内存页，在各级页目录/页表中分配所需的页目录/表项
	do {
		next = pgd_addr_end(addr, end);
		err = vmap_pud_range(pgd, addr, next, prot, pages);
		if (err)
			break;
	} while (pgd++, addr = next, addr != end);
	//刷新CPU高速缓存（IA-32体系的CPU不依赖于高速缓存刷出，处理为空过程）
	flush_cache_vmap((unsigned long) area->addr, end);
	return err;
}
```



- **`vunmap()`：释放内存区**
  - 

```
//addr：释放区域的起始地址
//deallocate_pages：指定了是否将与该区域相关的物理内存页返回给伙伴系统
static void __vunmap(void *addr, int deallocate_pages)
{
......
	area = remove_vm_area(addr);
......
	if (deallocate_pages) {
		for (i = 0; i < area->nr_pages; i++) {
			__free_page(area->pages[i]);
		}

		if (area->flags & VM_VPAGES)
			vfree(area->pages);
		else
			kfree(area->pages);
	}

	kfree(area);
	return;
}

/* Caller must hold vmlist_lock */
static struct vm_struct *__remove_vm_area(void *addr)
{
	struct vm_struct **p, *tmp;

	for (p = &vmlist ; (tmp = *p) != NULL ;p = &tmp->next) {
		 if (tmp->addr == addr)
			 goto found;
	}
	return NULL;

found:
	unmap_vm_area(tmp);
	*p = tmp->next;

	/*
	 * Remove the guard page.
	 */
	tmp->size -= PAGE_SIZE;
	return tmp;
}
static void unmap_vm_area(struct vm_struct *area)
{
	unmap_kernel_range((unsigned long)area->addr, area->size);
}
void unmap_kernel_range(unsigned long addr, unsigned long size)
{
	pgd_t *pgd;
	unsigned long next;
	unsigned long start = addr;
	unsigned long end = addr + size;

	BUG_ON(addr >= end);
	pgd = pgd_offset_k(addr);
	flush_cache_vunmap(addr, end);
	do {
		next = pgd_addr_end(addr, end);
		if (pgd_none_or_clear_bad(pgd))
			continue;
		vunmap_pud_range(pgd, addr, next);
	} while (pgd++, addr = next, addr != end);
	flush_tlb_kernel_range(start, end);
}
```





## 3.6 slab分配器
背景：内核需要分配小于4KB的内存空间
解决方案：引入slab分配器，将伙伴系统4K的页拆成更小单位分配
好处：
- 将页拆分成更小的单位，提升内存利用的速度和效率
- 作为缓存提效，减少对伙伴系统的调用。物理页帧 -> 伙伴系统 -> slab内部列表 -> 内核代码（图3-43）
- 通过slab着色，slab分配器能够均匀地分布对象，实现均匀的CPU高速缓存利用

### 3.6.1 备选分配器
slab分配器对一些情形无法提供最优性能，2.6内核提供了slob分配器和slub分配器优化。默认slab分配器
分配器API
- 内存分配：kmalloc、__kmalloc、kmalloc_node
- 内核缓存：kmem_cache_alloc、kmem_cache_alloc_node
- 便捷函数：kcalloc、kzalloc等

### 3.6.2 内核中的内存管理
1. kmem_cache_create创建有适当的缓存，使用kmem_cache_alloc/kmem_cache_free分配和释放对象。活动缓存列表保存在/proc/slabinfo
2. 使用kmalloc(size, flags)分配长度为size字节的内存区。这里内核会找到最适合的缓存并分配对象。其中，flags参数指定具体的内存域（如GFP_DMA指定适合于DMA的内存区），返回void*
3. 如果找不到缓存，slab分配器负责与伙伴系统交互，分配所需的页

### 3.6.3 slab分配的原理
组成：缓存对象、被管理对象的各个slab

图3-44
