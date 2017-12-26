/*********************************************************************************************************************** 
 *  (C) 2016-2017 Dorukhan Arslan. Released under the GPL.
 *  
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/
 **********************************************************************************************************************/

.data #############################################################################################################
###################################################################################################################
tape:	.skip	 32768, 0

# an array of u16s for data and an array of u8s for instructions
prgmsz: .quad 60000
max_prgmsz: .quad 60000

tapesz: .quad 32768 
## TODO: join these arrays also fold <,> into instruction to right as offset
prgm_aryptr: 	.quad 0	
prgmdt_aryptr:	.quad 0 

.text #############################################################################################################
###################################################################################################################
rdarg:	.asciz	"r"
fo: 	.asciz "%lu\n"
fz: 	.asciz "%lu %lu\n"

###################################################################################################################
# subroutine: compile
# convert brainfuck operators into an array of bytes, 
# skip all irrelevant chars, check unbalanced square brackets
compile: # compile(FILE* fileptr): void
   	pushq	%rbp
   	movq	%rsp, %rbp
	subq	$16, %rsp
	movq	%rdi, -8(%rbp) # -8 fileptr
	movq	$0, -16(%rbp) # -16 tmp_prgm_ptr
# malloc temporary prgm_ptr
	movq	(max_prgmsz), %rdi # u8 tmp_prgm_aryptr[prgmsz] 
	call	malloc
	cmpq	$-1, %rax
	je		error
	movq	%rax, -16(%rbp) 
# do pre pass, get updated program size	
	movq	-8(%rbp), %rsi # fileptr
	movq	-16(%rbp), %rdi # tmp_prgm_aryptr
	call	pre_pass
	incq	%rax
	mov		%rax, (prgmsz) # +1 for end instruction
# allocate prgmdt_aryptr
	shlq	$1, %rax # *2 for u16
	movq	%rax, %rdi
	call 	malloc # prgmdtaryptr
	cmpq	$-1, %rax
	je		error	
# allocate prgm_aryptr
	movq	%rax, (prgmdt_aryptr)
	movq	(prgmsz), %rdi
	call 	malloc
	cmpq	$-1, %rax
	je		error
	movq	%rax, (prgm_aryptr)
# call optimization passes
	movq	-16(%rbp), %rdi	
	call	rle_pass
	movq	-16(%rbp), %rdi		
	call	free # free old program instruction array, save 20kb
	cmpq	$-1, %rax
	je		error
	call	jmp_pass
# resize using realloc to new program size	
	movq	(prgm_aryptr), %rdi
	movq	(prgmsz), %rsi
	call	realloc
	cmpq	$-1, %rax
	je		error
	mov		%rax, (prgmsz)
	movq	(prgmdt_aryptr), %rdi
	movq	(prgmsz), %rsi
	shlq	$1, %rsi # *2 for u16
	call	realloc
	cmpq	$-1, %rax
	je		error
	movq	%rax, (prgmdt_aryptr)
##DEBUG: print all instructions
#	pushq	$0 #-24 itr
#wl1:
#	movq	-24(%rbp), %rcx	
#	movq	(prgm_aryptr), %rax
#	movzbq	(%rax, %rcx, 1), %rsi
#	cmpq	$0, %rsi
#	je	wl1done
#	movq	(prgmdt_aryptr), %rax
#	movzwq	(%rax, %rcx, 2), %rdx
#	movq	$0, %rax
#	movq	$fz, %rdi
#	call	printf
#wl1end:
#	incq	-24(%rbp)
#	jmp	wl1
#wl1done:
#	popq	%rax
#	movq	$5, %rdi
#	call	exit
##\DEBUG
cmplend: # fclose(fileptr: %rdi)
	movq	%rbp, %rsp # set sp to current bp
	popq	%rbp # restore caller's bp
	ret # void (junk %rax)

pre_pass: # u64 pre_pass(u8* tmp_prgm_aryptr, FILE* fileptr)
# returns programctr
   	pushq	%rbp
   	movq	%rsp, %rbp
# init relevant variables
   	subq	$48, %rsp # make space on tape	
	movq	%rsi, -8(%rbp) # fileptr
	movq	$0,  -16(%rbp) # progctr
	movq	$0,  -24(%rbp) # charin 				
	movq	$0,  -32(%rbp) # nlsqrb 
	movq	$0,  -40(%rbp) # nrsqrb				
	movq	%rdi, -48(%rbp) #-48 tmp_prgm_aryptr
pploop:	# while (charin != EOF && progctr < prgmsz)
   	movq	-8(%rbp), %rax
	movq	%rax, %rdi # arg1 
	call	getc # getc(fileptr: %rdi)
	cltq # getc returns u32 so convert to u64
	movq	%rax, -24(%rbp)	# charin = getc(fileptr)
	cmpq	$-1, -24(%rbp) # charin != EOF
	je		ppldone	# loop done
	cmpq	$prgmsz, -16(%rbp) # && prgctr < max_programsz
	jge		ppldone	# loop done
	movq	-24(%rbp), %rdx	# put charin into %rdx for quick access
	movq	-16(%rbp), %rcx # put progctr into %rcx for quick access	
cmcs1: 	# OPCODE 1 '>' increment tape pointer
	cmpq	$62, %rdx # charin == '>'
	jne		cmcs2
	movq	-48(%rbp), %rax # base: &prgm
	movb	$1, (%rax, %rcx) # *(base+progctr*sizeof(u8)) = 1
	jmp		pplend # loop
cmcs2: 	# OPCODE 2 '<' decrement tape pointer
	cmpq	$60, %rdx # charin == '<'
	jne		cmcs3	
	movq	-48(%rbp), %rax	# base: &prgm
	movb	$2, (%rax, %rcx) # *(base+index*scale) = 2
	jmp		pplend # loop
cmcs3: 	# OPCODE 3 '+' increment data at tape pointer
	cmpq	$43, %rdx # charin == '+'
	jne		cmcs4			
	movq	-48(%rbp), %rax	# base: &prgm
	movb	$3, (%rax, %rcx) # *(base+progctr*sizeof(u8)) = 3
	jmp		pplend # loop
cmcs4: 	# OPCODE 4 '-' decrement data at tape pointer
	cmpq	$45, %rdx # charin == '-'
	jne		cmcs5	
	movq	-48(%rbp), %rax # base: &prgm
	movb	$4, (%rax, %rcx) # *(base+progctr*sizeof(u8)) = 4
	jmp		pplend # loop
cmcs5: 	# OPCODE 5 '.' output data at tape pointer as a char
	cmpq	$46, %rdx # charin == '.'
	jne		cmcs6	
	movq	-48(%rbp), %rax # base: &prgm
	movb	$5, (%rax, %rcx) # *(base+progctr*sizeof(u8)) = 5
	jmp		pplend # loop
cmcs6: 	# OPCODE 6 ',' get input char from stdin to data at tape pointer
	cmpq	$44, %rdx # charin == ','
	jne		cmcs7			
	movq	-48(%rbp), %rax # base: &prgm
	movb	$6, (%rax, %rcx) # *(base+progctr*sizeof(u8)) = 6
	jmp		pplend # loop
cmcs7: 	# OPCODE 7 '[' jump to matching bracket if data at tape pointer is zero
	cmpq	$91, %rdx # charin == '['
	jne		cmcs8
	jmp		cmcszero # loop
cmcs8: # OPCODE 8 ']' jump to matching bracket if data at tape pointer is not zero
	cmpq	$93, %rdx # charin == ']'
	jne		cmcdf	
	movq	-48(%rbp), %rax	# base: &prgm
	movb	$8, (%rax, %rcx, 1) # *(base+progctr*sizeof(u8)) = 8
	incq	-40(%rbp) # nrsqrb += 1
	jmp		pplend
cmcszero: # OPCODE 9 '[-]' set data at tapeptr to zero
# nextchar  == '-'
    	movq	-8(%rbp), %rax
 	movq	%rax, %rdi # arg1 
 	call	getc # getc(fileptr: %rdi)
 	cltq # getc returns u32 so convert to u64
 	movq	%rax, -24(%rbp) # charin = getc(fileptr)
 	cmpq	$45, -24(%rbp) # charin == '-'
 	jne     cmugetc1
# nextchar == ']'
 	movq	-8(%rbp), %rax
 	movq	%rax, %rdi # arg1 
 	call	getc # getc(fileptr: %rdi)
 	cltq # getc returns u32 so convert to u64
 	movq	%rax, -24(%rbp)	# charin = getc(fileptr)
 	cmpq	$93, -24(%rbp)	# charin == ']'
 	jne     cmugetc2
# set opcode 9
	movq	-16(%rbp), %rcx	# put progctr into %rcx for quick access
	movq	-48(%rbp), %rax	# base: &prgm
	movb	$9, (%rax, %rcx, 1)	# *(base+progctr*sizeof(u8)) = ZERO
	jmp		pplend	# loop
cmugetc1:
	movq	-8(%rbp), %rax
	movq	%rax, %rsi # arg1 
	movq	-24(%rbp), %rdi
	call	ungetc
	movq	-48(%rbp), %rax	# base: &prgm
	movq	-16(%rbp), %rcx # put progctr into %rcx for quick access
	movb	$7, (%rax, %rcx, 1) # *(base+progctr*sizeof(u8)) = 8
	incq	-32(%rbp) # nrsqrb += 1
	jmp		pplend
cmugetc2:
	movq	-8(%rbp), %rax
	movq	%rax, %rsi # arg1 
	movq	-24(%rbp), %rdi	# charin = getc(fileptr)
	call	ungetc
	movq	-8(%rbp), %rax
	movq	%rax, %rsi # arg1 
	movq	$45, %rdi # charin = getc(fileptr)
	call	ungetc
	movq	-16(%rbp), %rcx	# put progctr into %rcx for quick access
	movq	-48(%rbp), %rax	# base: &prgm
	movb	$7, (%rax, %rcx, 1)	# *(base+progctr*sizeof(u8)) = 8
	incq	-32(%rbp) # nrsqrb += 1
	jmp		pplend # loop
cmcdf: 	# NOP not a character we're interested in, skip 
	decq	-16(%rbp) # progctr -= 1
	jmp 	pplend # loop
pplend:	# increment progctr and loop
	incq	-16(%rbp) # progctr += 1
	jmp		pploop
ppldone:# misc checks for syntax and size errors
	movq	-32(%rbp), %rax
	cmpq	%rax, -40(%rbp)	# unbalanced sqr brackets:
	jne		error # ->error bad syntax
	cmpq	$-1, -24(%rbp) # last character != EOF:
	jne		error # ->error input program exceeds prgmsz
	movq	-16(%rbp), %rcx	# load progctr
	movq	-48(%rbp), %rax	# base: &prgm
	movb	$0, (%rax, %rcx, 1)	# *(base+progctr*sizeof(u8)) = 0	
ppend:	# close file and return
	movq	-8(%rbp), %rdi # fileptr
	call	fclose
	movq	-16(%rbp), %rax # fclose(fileptr: %rdi)
	movq	%rbp, %rsp # set sp to current bp
	popq	%rbp # restore caller's bp
	ret	# tmp_prgm_aryptr (%rax)

###################################################################################################################	
# subroutine: rle_pass
# run-length instructions 1-4 to prevent unnecessary repeat instructions and save some space
rle_pass: # u64 rle_pass(u8* tmp_prgm_aryptr)
# returns new run-length encoded program size
   	pushq	%rbp
   	movq	%rsp, %rbp
	subq	$48, %rsp
	movq	%rdi, -8(%rbp)	# arg1 tmp_prgm_aryptr
	movq	$0, -16(%rbp) 	# pc
	movq	$0, -24(%rbp) 	# ipc
	movq	$0, -32(%rbp) 	# instr
	movq	$0, -40(%rbp) 	# iter
	movq	$0, -48(%rbp) 	# nextinstr
rleloop1: # while ((instr = program[pc]) != && pc < prgm_sz) | depth: 1
# loop1 condition
	movq	-8(%rbp), %rax
	movq	-16(%rbp), %rcx	
	movzbq	(%rax, %rcx, 1), %rax # tmp_prgm_aryptr[pc]
	movq	%rax, -32(%rbp)
	cmpq	$0, %rax
	je		rlel1done
	cmpq	(prgmsz), %rcx
	jge		rlel1done
# loop1 body
	addq	$1, %rcx
	movq	%rcx, -24(%rbp) # ipc=pc+1
	movq	-40(%rbp), %rcx # rcx = iter	
	movq	(prgmdt_aryptr), %rax
	movw	$1, (%rax, %rcx, 2) # prgm_dt_aryptr[iter] = 1
	movb	-32(%rbp), %bl	#instr
	movq	(prgm_aryptr), %rax 
	movb	%bl, (%rax, %rcx, 1) # prgm_aryptr[iter] = instr
# _if (instr > 0 && instr <= 4)
	cmpq	$0, %rbx
	jle		rlel1end
	cmpq 	$4, %rbx
	jg		rlel1end
rleloop2: # while ((nextinstr = program[ipc]) == instr) | depth: 2
# loop2 condition
	movq	-8(%rbp), %rax # tmp_prgm_aryptr
	movq	-24(%rbp), %rcx	# rcx = ipc
	movzbq	(%rax, %rcx, 1), %rax # rax = tmp_prgm_aryptr[ipc]
	movq	%rax, -48(%rbp) # nextinstr = rax
	cmpq	-32(%rbp), %rax # nextinstr == instr
	jne		rlel2done
# loop2 body
	movq	-40(%rbp), %rcx # rcx = iter
	movq	(prgmdt_aryptr), %rax
	incw	(%rax, %rcx, 2) # prgm_dt_aryptr+iter*2		
	#incw	(%rax) # prgm_dt_aryptr[iter] += 1
	incq	-24(%rbp) #ipc += 1	
rlel2end:
	jmp		rleloop2
rlel2done:
rlel1end:
	movq	-24(%rbp), %rbx # rbx = ipc
	movq	%rbx, -16(%rbp) # pc = rbx
	incq	-40(%rbp) # iter += 1
	jmp		rleloop1
rlel1done:
	# set last instruction to zero
	movq	-40(%rbp), %rcx
	incq	%rcx # iter+=1
	movq	(prgm_aryptr), %rax 
	movb	$0, (%rax, %rcx, 1) # prgm_aryptr[iter] = 0
	movq	%rcx, %rax
rlepend:											
	movq	%rbp, %rsp												
	popq	%rbp													
	ret	

###################################################################################################################	
# subroutine: jmp_pass
# precompute jump offset for matching square bracket operators
jmp_pass:
   	pushq	%rbp
   	movq	%rsp, %rbp
# init stuff
	subq	$40, %rsp
	movq	$0, -8(%rbp) # pc
	movq	$0, -16(%rbp) # ipc
	movq	$0, -24(%rbp) # instr
	movq	$0, -32(%rbp) # nextinstr
	movq	$0, -40(%rbp) # match
jmploop1: # while ((instr=prgm_aryptr[pc]) != 0) depth: 1
	movq	(prgm_aryptr), %rax 
	movq	-8(%rbp), %rcx # rcx = pc
	movzbq	(%rax, %rcx, 1), %rax # rax = *(rax+rcx*1)
	movq	%rax, -24(%rbp)
	cmpq	$0, %rax # if  instr == 0
	je		jmpl1done
	cmpq	$7, %rax # if instr == 7
	jne		jmpl1end
	movq	-8(%rbp), %rax  # ipc = pc
	movq	%rax, -16(%rbp) # ^^
	movq	$1, -40(%rbp) # match = 1	
jmploop2: # while (match > 0) depth: 2
	cmpq	$0, -40(%rbp) # match > 0
	jle		jmpl2done
	incq	-16(%rbp)
	movq	-16(%rbp), %rcx	# ipc+=1
	movq	(prgm_aryptr), %rax 
	movzbq	(%rax, %rcx, 1), %rax # rax = *(rax+rcx*1)
	movq	%rax, -32(%rbp) # nextinstr = prgm_aryptr[++ipc]
	cmpq	$8, %rax
	jne		mlelif
	decq	-40(%rbp)
	jmp		jmpl2end
mlelif:
	cmpq	$7, %rax
	jne		jmpl2end
	incq	-40(%rbp)
jmpl2end:
	jmp 	jmploop2
jmpl2done:
	movw	-16(%rbp), %r8w
	subw	-8(%rbp), %r8w
	movq	(prgmdt_aryptr), %rax
	movq	-8(%rbp), %rcx
	movw	%r8w, (%rax, %rcx, 2) # prgmdt_aryptr[pc] = ipc-pc
	movq	-16(%rbp), %rcx # rcx = ipc
	movw	%r8w, (%rax, %rcx, 2) # prgmdt_aryptr[ipc] = ipc-pc
jmpl1end:
	incq	-8(%rbp)
	jmp		jmploop1
jmpl1done:
jmppdone:
	movq	%rbp, %rsp # set sp to current bp
	popq	%rbp # restore caller's bp
	ret	

###################################################################################################################	
# subroutine: exec
# run program using instructions generated by the compile subroutine

dbform:	.asciz	"%d %d\n"

# jumptable for switch cases
ecjt:
.quad 	ecs0
.quad 	ecs1
.quad 	ecs2
.quad 	ecs3
.quad 	ecs4
.quad 	ecs5
.quad 	ecs6
.quad 	ecs7
.quad 	ecs8
.quad 	ecs9
.quad 	ecsd

# switch cases
ecs0:	# OPCODE 0 we've successfully brainfucked!
	jmp 	success
ecs1:	# OPCODE 1 '>' increment tape pointer by amount in prgmdt_aryptr[progctr]
	movq	(prgmdt_aryptr), %rax # get base of program array
	movzwq	(%rax, %rcx, 2), %rax	
	shlq	$1, %rax # *=2 because data size in tape is u16	
	addq	%rax, -8(%rbp) # tapeptr += prgmdt_aryptr[progctr]
	jmp 	eloop1end # loop
ecs2:	# OPCODE 2 '<' decrement tape pointer by amount in prgmdt_aryptr[progctr]
	movq	(prgmdt_aryptr), %rax # get base of program array
	movzwq	(%rax, %rcx, 2), %rax	
	shlq	$1, %rax # *=2 because data size in tape is u16	
	subq	%rax, -8(%rbp) # tapeptr -= prgmdt_aryptr[progctr]
	jmp		eloop1end # loop
ecs3:	# OPCODE 3 '+' increment data at tape pointer by amount in prgmdt_aryptr[progctr]
	movq	(prgmdt_aryptr), %r8 # get base of program array
	movzwq	(%r8, %rcx, 2), %r8	
	movq	-8(%rbp), %rbx # %rbx = tapeptr
	movzwq	(%rbx), %rax # %rax = *%rbx
	addw	%r8w, %ax # %ax += prgmdt_aryptr[progctr]
	movw	%ax, (%rbx) # *tapeptr = %ax
	jmp		eloop1end # loop
ecs4:	# OPCODE 4 '-' decrement data at tape pointer by amount in prgmdt_aryptr[progctr]
	movq	(prgmdt_aryptr), %r8 # get base of program array
	movzwq	(%r8, %rcx, 2), %r8		
	movq	-8(%rbp), %rbx # %rbx = tapeptr
	movzwq	(%rbx), %rax # %rax = *%rbx
	subw	%r8w, %ax # %ax -= prgmdt_aryptr[progctr]
	movw	%ax, (%rbx)	# *tapeptr = %ax
	jmp		eloop1end # loop
ecs5:	# OPCODE 5 '.' output data at tape pointer as a char 
	movq	-8(%rbp), %rbx # %rbx = tapeptr
	movzwq	(%rbx), %rdi # arg 1 %rdi = *%rbx
	call	putchar								
	jmp		eloop1end # loop	
ecs6:	# OPCODE 6 ',' get input char from stdin to data at tape pointer
	call	getchar	# %rax = getchar()
	movq	-8(%rbp), %rbx # %rbx = tapeptr
	movw	%ax, (%rbx) # *%rbx = (u16) %rax
	jmp		eloop1end # loop
ecs7:	# OPCODE 7 '[' jump to matching bracket if data at tape pointer is zero	
	movq	-8(%rbp), %rbx # %rbx = tapeptr
	movzwq	(%rbx), %rax # %rax = *%rbx
	cmpq	$0, %rax # if (%rax == 0)
	jne		eloop1end # don't break							
	movq	(prgmdt_aryptr), %r8 # get base of program array
	movzwq	(%r8, %rcx, 2), %r8									
	addq	%r8, -16(%rbp) # jump forward by offset specified in prgmdt_aryptr[progctr]
	jmp 	eloop1end												
ecs8:	# OPCODE 8 ']' jump to matching bracket if data at tape pointer is not zero	
	movq	-8(%rbp), %rbx # %rbx = tapeptr
	movzwq	(%rbx), %rax # %rax = *%rbx
	cmpq	$0, %rax # if (%rax == 0)
	je		eloop1end # don't break							
	movq	(prgmdt_aryptr), %r8 # get base of program array
	movzwq	(%r8, %rcx, 2), %r8
	subq	%r8, -16(%rbp) # jump backward by offset specified in prgmdt_aryptr[progctr]
	jmp 	eloop1end												
ecs9:	# OPCODE 9 '[-]' set data at tape pointer to zero
	movq	-8(%rbp), %rbx # %rbx = tapeptr
	movw	$0, (%rbx) # *tapeptr = %ax
	jmp		eloop1end # loop
ecsd:
	jmp		error

exec: # exec(): void
	pushq	%rbp
   	movq	%rsp, %rbp
   	subq	$24, %rsp
   	lea		tape, %rax #  &tape: %rax
   	movq	%rax, -8(%rbp) #  -8 tapeptr = &tape
   	movq	$0,  -16(%rbp) # -16 progctr = 0
   	movq	$0,  -24(%rbp) # -24 op	= 0
eloop1:
	movq	-16(%rbp), %rcx
	cmpq	(prgmsz), %rcx	# if < prgmsz
	movq	(prgm_aryptr), %rax # get base of program array
	movzbq	(%rax, %rcx, 1), %rax # deref and ld back
	movq	%rax, -24(%rbp) # op = rax
##	dbg
#	movq	-8(%rbp), %rbx												# %rbx = tapeptr
#	movzwq	(%rbx), %rdx												# arg3 VALUE *%rbx
#	movq	%rax,%rsi												# arg2 OPCODE
#	movq	$dbform, %rdi												# arg1 format string
#	movq	$0, %rax												# no vargs
#	call	printf														
#	movq	-24(%rbp), %rax												# restore
##	dbg
	shlq	$3, %rax # op * 8
	movq	ecjt(%rax), %rax # &ecjt + %rax
	jmp		*%rax # deref and jump to addr
eloop1end:
	incq	-16(%rbp)
	jmp		eloop1
execend:
	movq	%rbp, %rsp # set sp to current bp
	popq	%rbp # restore caller's bp
	ret # void (junk %rax)

.global main ######################################################################################################
.type main @function
main:
   	pushq	%rbp
   	movq	%rsp, %rbp
   	cmpl	$2, %edi # if argc != 2
   	jne		error # error (return 1)
   	addq	$8, %rsi # &argv+sizeof(char*)
   	pushq	(%rsi) # deref once to access argv[1]: -8 u64 &filename
   	movq	-8(%rbp), %rdi										
   	movq	$rdarg, %rsi # arg2 fopen
   	call	fopen # returns FILE*
   	cmpq	$0, %rax # if FILE* == NULL
   	je		error # error (return 1)
   	pushq	%rax # -16 u64 fileptr
# compile(fileptr)
	movq	-16(%rbp), %rdi
	call	compile
# exec()
	call	exec
	jmp		success
mainend:
	movq	%rbp, %rsp
	call	exit	
error:
	movq	$1, %rdi
	jmp		mainend
success:
	movq	$0, %rdi
	jmp		mainend
