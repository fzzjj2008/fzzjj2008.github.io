	.file	"main.c"
	.text
	.globl	thread
	.type	thread, @function
thread:
.LFB41:
	.cfi_startproc
	endbr64
	movq	(%rdi), %rcx
	movl	$0, %edx
.L2:
	cmpq	%rcx, %rdx
	jge	.L4
	movq	cnt(%rip), %rax
	addq	$1, %rax
	movq	%rax, cnt(%rip)
	addq	$1, %rdx
	jmp	.L2
.L4:
	movl	$0, %eax
	ret
	.cfi_endproc
.LFE41:
	.size	thread, .-thread
	.section	.rodata.str1.1,"aMS",@progbits,1
.LC0:
	.string	"usage: %s <niters>\n"
.LC1:
	.string	"BOOM! cnt = %ld\n"
.LC2:
	.string	"OK! cnt = %ld\n"
	.text
	.globl	main
	.type	main, @function
main:
.LFB40:
	.cfi_startproc
	endbr64
	pushq	%rbx
	.cfi_def_cfa_offset 16
	.cfi_offset 3, -16
	subq	$32, %rsp
	.cfi_def_cfa_offset 48
	movq	%fs:40, %rax
	movq	%rax, 24(%rsp)
	xorl	%eax, %eax
	cmpl	$2, %edi
	je	.L6
	movq	(%rsi), %rdx
	leaq	.LC0(%rip), %rsi
	movl	$1, %edi
	call	__printf_chk@PLT
	movl	$0, %edi
	call	exit@PLT
.L6:
	movq	8(%rsi), %rdi
	movl	$10, %edx
	movl	$0, %esi
	call	strtol@PLT
	cltq
	movq	%rax, (%rsp)
	movq	%rsp, %rbx
	leaq	8(%rsp), %rdi
	movq	%rbx, %rcx
	leaq	thread(%rip), %rdx
	movl	$0, %esi
	call	pthread_create@PLT
	leaq	16(%rsp), %rdi
	movq	%rbx, %rcx
	leaq	thread(%rip), %rdx
	movl	$0, %esi
	call	pthread_create@PLT
	movl	$0, %esi
	movq	8(%rsp), %rdi
	call	pthread_join@PLT
	movl	$0, %esi
	movq	16(%rsp), %rdi
	call	pthread_join@PLT
	movq	(%rsp), %rax
	addq	%rax, %rax
	movq	cnt(%rip), %rdx
	cmpq	%rdx, %rax
	je	.L7
	movq	cnt(%rip), %rdx
	leaq	.LC1(%rip), %rsi
	movl	$1, %edi
	movl	$0, %eax
	call	__printf_chk@PLT
.L8:
	movq	24(%rsp), %rax
	xorq	%fs:40, %rax
	jne	.L11
	movl	$0, %eax
	addq	$32, %rsp
	.cfi_remember_state
	.cfi_def_cfa_offset 16
	popq	%rbx
	.cfi_def_cfa_offset 8
	ret
.L7:
	.cfi_restore_state
	movq	cnt(%rip), %rdx
	leaq	.LC2(%rip), %rsi
	movl	$1, %edi
	movl	$0, %eax
	call	__printf_chk@PLT
	jmp	.L8
.L11:
	call	__stack_chk_fail@PLT
	.cfi_endproc
.LFE40:
	.size	main, .-main
	.globl	cnt
	.bss
	.align 8
	.type	cnt, @object
	.size	cnt, 8
cnt:
	.zero	8
	.ident	"GCC: (Ubuntu 9.4.0-1ubuntu1~20.04.1) 9.4.0"
	.section	.note.GNU-stack,"",@progbits
	.section	.note.gnu.property,"a"
	.align 8
	.long	 1f - 0f
	.long	 4f - 1f
	.long	 5
0:
	.string	 "GNU"
1:
	.align 8
	.long	 0xc0000002
	.long	 3f - 2f
2:
	.long	 0x3
3:
	.align 8
4:
