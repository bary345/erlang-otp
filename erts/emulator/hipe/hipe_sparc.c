/* $Id$
 */
#include <stddef.h>	/* offsetof() */
#ifdef HAVE_CONFIG_H
#include "config.h"
#endif
#include "global.h"

#include "hipe_arch.h"
#include "hipe_native_bif.h"	/* nbif_callemu() */

/* Flush dcache and invalidate icache for a range of addresses. */
void hipe_flush_icache_range(void *address, unsigned int nbytes)
{
    char *a = (char*)address;
    int n = nbytes;

    while( n > 0 ) {
	hipe_flush_icache_word(a);
	a += 4;
	n -= 4;
    }
}

static void patch_sethi(Uint32 *address, unsigned int imm22)
{
    unsigned int insn = *address;
    *address = (insn & 0xFFC00000) | (imm22 & 0x003FFFFF);
    hipe_flush_icache_word(address);
}

static void patch_ori(Uint32 *address, unsigned int imm10)
{
    /* address points to an OR reg,imm,reg insn */
    unsigned int insn = *address;
    *address = (insn & 0xFFFFE000) | (imm10 & 0x3FF);
    hipe_flush_icache_word(address);
}

static void patch_sethi_ori(Uint32 *address, Uint32 value)
{
    patch_sethi(address, value >> 10);
    patch_ori(address+1, value);
}

void hipe_patch_load_fe(Uint32 *address, Uint32 value)
{
    patch_sethi_ori(address, value);
}

int hipe_patch_insn(void *address, Uint32 value, Eterm type)
{
    switch (type) {
    case am_load_mfa:
    case am_atom:
    case am_constant:
    case am_closure:
    case am_c_const:
	break;
    default:
	return -1;
    }
    patch_sethi_ori((Uint32*)address, value);
    return 0;
}

int hipe_patch_call(void *callAddress, void *destAddress, void *trampoline)
{
    Uint32 relDest, newI;

    if (trampoline)
	return -1;
    relDest = (Uint32)((Sint32)destAddress - (Sint32)callAddress);
    newI = (1 << 30) | (relDest >> 2);
    *(Uint32*)callAddress = newI;
    hipe_flush_icache_word(callAddress);
    return 0;
}

/* called from hipe_bif0.c:hipe_bifs_make_native_stub_2()
   and hipe_bif0.c:hipe_make_stub() */
void *hipe_make_native_stub(void *beamAddress, unsigned int beamArity)
{
    unsigned int *code;
    unsigned int callEmuOffset;
    int i;
    
    code = erts_alloc(ERTS_ALC_T_HIPE, 5*sizeof(int));

    /* sethi %hi(Address), %g1 */
    code[0] = 0x03000000 | (((unsigned int)beamAddress >> 10) & 0x3FFFFF);
    /* or %g0, %o7, %l6 ! mov %o7, %l6 */
    code[1] = 0xAC10000F;
    /* or %g1, %lo(Address), %g1 */
    code[2] = 0x82106000 | ((unsigned int)beamAddress & 0x3FF);
    /* call callemu */
    callEmuOffset = (char*)nbif_callemu - (char*)&code[3];
    code[3] = (1 << 30) | ((callEmuOffset >> 2) & 0x3FFFFFFF);
    /* or %g0, Arity, %l7 ! mov Arity, %l7 */
    code[4] = 0xAE102000 | (beamArity & 0x0FFF);

    /* flush I-cache as if by write_u32() */
    for(i = 0; i < 5; ++i)
	hipe_flush_icache_word(&code[i]);

    return code;
}

void hipe_arch_print_pcb(struct hipe_process_state *p)
{
#define U(n,x) \
    printf(" % 4d | %s | 0x%08x |            |\r\n", offsetof(struct hipe_process_state,x), n, (unsigned)p->x)
    U("nra        ", nra);
    U("ncra       ", ncra);
#undef U
}
