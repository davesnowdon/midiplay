
; if non-zero, there are no border effects, and code size is smaller by 5 bytes
NO_BORDER_FX            equ     0
; if non-zero, code size decreases by 11 bytes at the expense of ~2% slowdown
SIZE_OPTIMIZED          equ     0
; total table size is 156 bytes, and should not cross a 256-byte page boundary
;decodeTablesBegin      equ     0ff4ch

nLengthSlots            equ     8
nOffs1Slots             equ     4
nOffs2Slots             equ     8
maxOffs3Slots           equ     32

        assert  decodeTablesBegin >= ((decodeTablesEnd - 1) & 0ff00h)

;       org   0fe40h

; input parameters:
;   HL:               source address (forward decompression)
;   DE:               destination address
; output parameters:
;   HL':              last source byte address + 1
;   HL:               same as HL', or undefined if SIZE_OPTIMIZED is non-zero
;   DE:               last written byte address + 1
;   AF, BC, BC', DE': undefined
;   AF', IX, IY:      not changed

decompressData:
        push  hl
        exx
        pop   hl                        ; HL' = compressed data read address
        inc   hl                        ; skip checksum byte
        ld    e, 80h                    ; initialize shift register (E')
.l1:    xor   a
        ld    c, a
        ld    b, a
        exx
        ld    bc, 1001h
        ld    h, a
        call  readBits16                ; read the number of symbols (HL)
        ld    c, 0                      ; set C = 0 for read2Bits/readBits
        call  read2Bits                 ; read flag bits
        srl   a
        push  af                        ; save last block flag (A=1, Z=0: yes)
        jr    nc, .l14                  ; uncompressed data ?
        call  read2Bits                 ; get prefix size for >= 3 byte matches
        push  de                        ; save decompressed data write address
        push  hl
        exx
        ld    b, a
        ld    a, 02h                    ; len >= 3 offset slots: 4, 8, 16, 32
        ld    d, 80h                    ; prefix size codes: 40h, 20h, 10h, 08h
        inc   b
.l2:    rlca
        srl   d                         ; D' = prefix size code for length >= 3
        djnz  .l2
        pop   bc                        ; store the number of symbols in BC'
        exx
        add   a, nLengthSlots + nOffs1Slots + nOffs2Slots - 3
        ld    b, a                      ; store total table size - 3 in B
        ld    hl, decodeTablesBegin     ; initialize decode tables
.l3:    ld    de, 1
.l4:    ld    a, 10h                    ; NOTE: C is 0 here, as set above
        call  readBits
        ld    (hl), a                   ; store the number of bits to read
        inc   hl
        ld    (hl), e                   ; store base value LSB
        inc   hl
        ld    (hl), d                   ; store base value MSB
        inc   hl
        push  hl
        ld    hl, 1                     ; calculate 2 ^ nBits
        jr    z, .l6                    ; readBits sets Z = 1 if A = 0
.l5:    add   hl, hl
        dec   a
        jr    nz, .l5
.l6:    add   hl, de                    ; calculate new base value
        ex    de, hl
        pop   hl
        ld    a, l
        cp    low offs1DecodeTable
        jr    z, .l3                    ; end of length decode table ?
        cp    low offs2DecodeTable
        jr    z, .l3                    ; end of offset table for length = 1 ?
        cp    low offs3DecodeTable
        jr    z, .l3                    ; end of offset table for length = 2 ?
        djnz  .l4                       ; continue until all tables are read
        pop   de                        ; DE = decompressed data write address
        jr    .l9                       ; jump to main decompress loop
.l7:    pop   af                        ; check last block flag:
        jr    z, .l1                    ; more blocks remaining ?
    if SIZE_OPTIMIZED == 0
        push  hl                        ; return last read address + 1 in HL',
    endif
        exx
    if SIZE_OPTIMIZED == 0
        pop   hl                        ; and HL
    endif
    if NO_BORDER_FX == 0
        xor   a                         ; reset border color
        out   (81h), a
    endif
        ret
.l8:    ld    a, (hl)                   ; copy literal byte
        inc   hl
        exx
        ld    (de), a
        inc   de
.l9:    exx
.l10:   ld    a, c                      ; check the data size remaining:
        or    b
        jr    z, .l7                    ; end of block ?
        dec   bc
        sla   e                         ; read flag bit
    if SIZE_OPTIMIZED == 0
        jr    nz, .l11
        ld    e, (hl)
        inc   hl
        rl    e
    else
        call  z, readCompressedByte
    endif
.l11:   jr    nc, .l8                   ; literal byte ?
        ld    a, 0f8h
.l12:   sla   e                         ; read length prefix bits
    if SIZE_OPTIMIZED == 0
        jr    nz, .l13
        ld    e, (hl)
        inc   hl
        rl    e
    else
        call  z, readCompressedByte
    endif
.l13:   jr    nc, copyLZMatch           ; LZ77 match ?
        inc   a
        jr    nz, .l12
        exx                             ; literal sequence:
        ld    bc, 0811h                 ; 0b1, 0b11111111, 0bxxxxxxxx
        ld    h, a
        call  readBits16                ; length is 8-bit value + 17
.l14:   ld    c, l                      ; copy literal sequence,
        ld    b, h                      ; or uncompressed block
        exx
        push  hl
        exx
        pop   hl
        ldir
        push  hl
        exx
        pop   hl
        jr    .l10                      ; return to main decompress loop

copyLZMatch:
        exx
        ld    b, low (lengthDecodeTable + 24)
        call  readEncodedValue          ; decode match length
        ld    c, 20h                    ; C = 20h: not readBits routine
        or    h                         ; if length <= 255, then A and H are 0
        jr    nz, .l6                   ; length >= 256 bytes ?
        ld    b, l
        djnz  .l5                       ; length > 1 byte ?
        ld    b, low offs1DecodeTable   ; no, read 2 prefix bits
.l1:    ld    a, 40h                    ; read2Bits routine if C is 0
.l2:    exx                             ; readBits routine if C is 0
.l3:    sla   e                         ; if C is FFh, read offset prefix bits
    if SIZE_OPTIMIZED == 0
        jp    nz, .l4
        ld    e, (hl)
        inc   hl
        rl    e
    else
        call  z, readCompressedByte
    endif
.l4:    rla
        jr    nc, .l3
        exx
        cp    c
        ret   nc
        push  hl
        call  readEncodedValue          ; decode match offset
        ld    a, e                      ; calculate LZ77 match read address
    if NO_BORDER_FX == 0
        out   (81h), a
    endif
        sub   l
        ld    l, a
        ld    a, d
        sbc   a, h
        ld    h, a
        pop   bc
        ldir                            ; copy match data
        jr    decompressData.l9         ; return to main decompress loop
.l5:    djnz  .l6                       ; length > 2 bytes ?
        ld    a, c                      ; no, read 3 prefix bits (C = 20h)
        ld    b, low offs2DecodeTable
        jr    .l2
.l6:    exx                             ; length >= 3 bytes,
        ld    a, d                      ; variable prefix size
        exx
        ld    b, low offs3DecodeTable
        jr    .l2

; NOTE: C must be 0 when calling these
read2Bits       equ     copyLZMatch.l1
; read 1 to 8 bits to A for A = 80h, 40h, 20h, 10h, 08h, 04h, 02h, 01h
readBits        equ     copyLZMatch.l2

readEncodedValue:
        ld    l, a                      ; calculate table address L (3 * A + B)
        add   a, a
        add   a, l
        add   a, b
        ld    l, a
        ld    h, high decodeTablesBegin
        ld    b, (hl)                   ; B = number of prefix bits
        inc   l
        ld    c, (hl)                   ; AC = base value
        inc   l
        ld    h, (hl)
        xor   a

; read B bits to HL, and add HC to the result; A must be zero

readBits16:
        ld    l, c
        cp    b
        ret   z
        ld    c, a
.l1:    exx
        sla   e
    if SIZE_OPTIMIZED == 0
        jp    nz, .l2
        ld    e, (hl)
        inc   hl
        rl    e
    else
        call  z, readCompressedByte
    endif
.l2:    exx
        rl    c
        rla
        djnz  .l1
        ld    b, a
        add   hl, bc
        ret

    if SIZE_OPTIMIZED != 0
readCompressedByte:
        ld    e, (hl)
        inc   hl
        rl    e
        ret
    endif

        assert  ($ <= decodeTablesBegin) || (decompressData >= decodeTablesEnd)

