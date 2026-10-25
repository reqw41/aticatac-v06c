; ZX0 classic decompressor (i8080), Ivan Gorodetsky / Scuba Dive.
; IN: DE=src compressed, BC=dst
dzx0:
	ld hl,0FFFFh
	push hl
	inc hl
	ld a,080h
dzx0_literals:
	call dzx0_elias
	call dzx0_ldir
	jp c,dzx0_new_offset
	call dzx0_elias
dzx0_copy:
	ex de,hl
	ex (sp),hl
	push hl
	add hl,bc
	ex de,hl
	call dzx0_ldir
	ex de,hl
	pop hl
	ex (sp),hl
	ex de,hl
	jp NC,dzx0_literals
dzx0_new_offset:
	call dzx0_elias
	ld h,a
	pop af
	xor a
	sub L
	ret z
	push hl
	rra
	ld h,a
	ld a,(de)
	rra
	ld l,a
	inc de
	ex (sp),hl
	ld A,H
	ld hl,1
	call nc,dzx0_elias_backtrack
	inc hl
	jp dzx0_copy
dzx0_elias:
	inc l
dzx0_elias_loop:
	add a,a
	jp NZ,dzx0_elias_skip
	ld a,(de)
	inc de
	rla
dzx0_elias_skip:
	ret C
dzx0_elias_backtrack:
	add hl,hl
	add a,a
	jp NC,dzx0_elias_loop
	jp dzx0_elias
dzx0_ldir:
	push af
dzx0_ldir1:
	ld a,(de)
	ld (bc),A
	inc de
	inc bc
	dec hl
	ld a,h
	or l
	jp nz,dzx0_ldir1
	pop af
	add a,a
	ret
