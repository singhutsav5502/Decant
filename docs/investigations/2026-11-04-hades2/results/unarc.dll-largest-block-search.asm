6108a8a9:      	nop
6108a8aa:      	nop
6108a8ab:      	nop
6108a8ac:      	nop
6108a8ad:      	nop
6108a8ae:      	nop
6108a8af:      	nop
6108a8b0:      	pushl	%ebp
6108a8b1:      	pushl	%edi
6108a8b2:      	pushl	%esi
6108a8b3:      	pushl	%ebx
6108a8b4:      	subl	$0xc, %esp
6108a8b7:      	movl	0x20(%esp), %esi
6108a8bb:      	movl	$0x0, (%esi)
6108a8c1:      	movl	$0x0, %ebp
6108a8c6:      	movl	$0xffffffff, %edi       # imm = 0xFFFFFFFF
6108a8cb:      	movl	%esi, (%esp)
6108a8ce:      	calll	0x6108aad2 <FreeArcExtract+0x64e2>
6108a8d3:      	leal	(%ebp,%edi), %eax
6108a8d7:      	movl	%eax, %ebx
6108a8d9:      	shrl	%ebx
6108a8db:      	movl	%ebx, 0x4(%esp)
6108a8df:      	movl	%esi, (%esp)
6108a8e2:      	calll	0x6108aa98 <FreeArcExtract+0x64a8>
6108a8e7:      	cmpl	$0x0, (%esi)
6108a8ea:      	je	0x6108a8f0 <FreeArcExtract+0x6300>
6108a8ec:      	movl	%ebx, %ebp
6108a8ee:      	jmp	0x6108a8f2 <FreeArcExtract+0x6302>
6108a8f0:      	movl	%ebx, %edi
6108a8f2:      	movl	%edi, %eax
6108a8f4:      	subl	%ebp, %eax
6108a8f6:      	cmpl	$0x1, %eax
6108a8f9:      	ja	0x6108a8cb <FreeArcExtract+0x62db>
6108a8fb:      	addl	$0xc, %esp
6108a8fe:      	popl	%ebx
6108a8ff:      	popl	%esi
6108a900:      	popl	%edi
6108a901:      	popl	%ebp
6108a902:      	retl
6108a903:      	nop
6108a904:      	pushl	%ebp
6108a905:      	pushl	%edi
6108a906:      	pushl	%esi
6108a907:      	pushl	%ebx
6108a908:      	subl	$0xc, %esp
6108a90b:      	movl	0x20(%esp), %esi
6108a90f:      	movl	$0x0, (%esi)
6108a915:      	movl	$0x0, %ebp
6108a91a:      	movl	$0xffffffff, %edi       # imm = 0xFFFFFFFF
6108a91f:      	movl	%esi, (%esp)
6108a922:      	calll	0x6108aad2 <FreeArcExtract+0x64e2>
6108a927:      	leal	(%ebp,%edi), %eax
6108a92b:      	movl	%eax, %ebx
6108a92d:      	shrl	%ebx
6108a92f:      	movl	%ebx, 0x4(%esp)
6108a933:      	movl	%esi, (%esp)
