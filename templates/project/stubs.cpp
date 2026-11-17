/*
 * Monster Madness: Grave Danger (BLUS30140) -- game-specific hooks.
 *
 * Loads Sony's real SPURS/Sync library (libsre.prx, lifted locally from the
 * user's own firmware) so the game's cellSpurs/cellSync imports reach the real
 * implementation instead of the HLE. The generated libsre_*.inc / libsre_defs.h
 * and everything under recompiled/ are derived from firmware: never commit them.
 */
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <cstdint>

#include "ppu_context.h"
#include "../../runtime/prx/prx_loader.h"
#include "libsre_defs.h"

extern "C" {
extern uint8_t* vm_base;
void ps3_hle_call(uint32_t nid, ppu_context* ctx);
void ppu_register_function(uint64_t addr, void (*fn)(ppu_context*));
typedef struct { uint64_t addr; void (*func)(ppu_context*); const char* name; } mm_func_entry;
extern const mm_func_entry libsre_function_table[];
extern const uint64_t      libsre_function_table_count;
}

/* Scratch guest addresses for the import bridge, above the libsre image. */
#define MM_BRIDGE_OPD   (LIBSRE_BASE + 0x00100000u)   /* 8 bytes per import */
#define MM_BRIDGE_CODE  (LIBSRE_BASE + 0x00110000u)   /* 4 bytes per import */

struct mm_import { uint32_t nid; uint32_t slot; };

static const prx_export k_exports[] = {
#include "libsre_exports.inc"
};
static const mm_import k_imports[] = {
#include "libsre_imports.inc"
};
static const uint32_t k_export_n = (uint32_t)(sizeof(k_exports) / sizeof(k_exports[0]));
static const uint32_t k_import_n = (uint32_t)(sizeof(k_imports) / sizeof(k_imports[0]));

static void be32w(uint32_t ea, uint32_t v)
{
    uint8_t* p = vm_base + ea;
    p[0] = (uint8_t)(v >> 24); p[1] = (uint8_t)(v >> 16); p[2] = (uint8_t)(v >> 8); p[3] = (uint8_t)v;
}
static uint32_t be32r(const uint8_t* p)
{
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

/* One host function serves every bridged import: the guest reached it through
 * an OPD whose code address encodes the import index. */
static void mm_libsre_import_bridge(ppu_context* ctx)
{
    const uint32_t i = ((uint32_t)ctx->ctr - MM_BRIDGE_CODE) / 4u;
    if (i < k_import_n) ps3_hle_call(k_imports[i].nid, ctx);
}

static void mm_register(uint32_t guest_addr, void (*host)(void*))
{
    ppu_register_function(guest_addr, (void (*)(ppu_context*))host);
}

/* ---- SPUJobs: the game's own PRX. Loaded at startup, started when the game asks. ---- */
extern "C" {
extern const mm_func_entry spujobs_function_table[];
extern const uint64_t      spujobs_function_table_count;
void     ps3_hle_register_ctx(uint32_t nid, const char* name, void (*fn)(ppu_context*));
uint64_t ppu_guest_call(uint32_t opd, uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3,
                        uint64_t a4, uint64_t a5, uint64_t a6, uint64_t a7);
}
#define MM_SPUJOBS_BASE      0x02200000u
#define MM_SPUJOBS_START_OPD 0x0220FA00u
#define MM_SPUJOBS_ID        0x23000100u
static int s_spujobs_loaded = 0;
static void mm_sys_prx_load_module(ppu_context* ctx)
{
    const char* path = (const char*)(vm_base + (uint32_t)ctx->gpr[3]);
    fprintf(stderr, "[mm] sys_prx_load_module('%s') loaded=%d\n", path, s_spujobs_loaded);
    ctx->gpr[3] = s_spujobs_loaded ? (uint64_t)MM_SPUJOBS_ID : (uint64_t)(int64_t)(int32_t)0x8001112Eu;
}
static void mm_sys_prx_start_module(ppu_context* ctx)
{
    const uint32_t id = (uint32_t)ctx->gpr[3], argp = (uint32_t)ctx->gpr[5], modres = (uint32_t)ctx->gpr[6];
    const uint64_t args = ctx->gpr[4];
    uint64_t rc = 0;
    if (id == MM_SPUJOBS_ID) rc = ppu_guest_call(MM_SPUJOBS_START_OPD, args, argp, 0, 0, 0, 0, 0, 0);
    if (modres) be32w(modres, (uint32_t)rc);
    fprintf(stderr, "[mm] sys_prx_start_module(id=0x%08X args=%u argp=0x%08X) rc=%d", id, (unsigned)args, argp, (int)rc);
    if (argp) for (uint32_t k = 0; k < 16u; k += 4u) fprintf(stderr, " %08X", be32r(vm_base + argp + k));
    fprintf(stderr, "\n");
    ctx->gpr[3] = 0;
}
/* MM: two imports the game calls that had no HLE handler at all.
 *  cellGameDataGetSizeKB (0xA9B0C1D9): called once at boot; report 0 KB used.
 *  inet_addr (0xDABBC2C0): registered by sys_net only in PS3_NET_ONLINE mode;
 *  offline it fell to the unresolved default. Pure string parse, no network. */
static void mm_cellGameDataGetSizeKB(ppu_context* ctx)
{
    const uint32_t out = (uint32_t)ctx->gpr[3];
    if (out) be32w(out, 0);
    ctx->gpr[3] = 0;
}
static void mm_inet_addr(ppu_context* ctx)
{
    const uint32_t sp = (uint32_t)ctx->gpr[3];
    uint32_t v = 0xFFFFFFFFu;
    if (sp) {
        const char* str = (const char*)(vm_base + sp);
        unsigned a, b, c, d; char tail;
        if (sscanf(str, "%u.%u.%u.%u%c", &a, &b, &c, &d, &tail) == 4 && a < 256 && b < 256 && c < 256 && d < 256)
            v = (a << 24) | (b << 16) | (c << 8) | d;   /* network order == guest big-endian value */
    }
    ctx->gpr[3] = v;
}
static void mm_load_spujobs(void)
{
    ps3_hle_register_ctx(0xA9B0C1D9u, "cellGameDataGetSizeKB", mm_cellGameDataGetSizeKB);
    if (!getenv("PS3_NET_ONLINE")) ps3_hle_register_ctx(0xDABBC2C0u, "inet_addr", mm_inet_addr);
    ps3_hle_register_ctx(0x26090058u, "sys_prx_load_module", mm_sys_prx_load_module);
    ps3_hle_register_ctx(0x9F18429Du, "sys_prx_start_module", mm_sys_prx_start_module);
    uint32_t size = 0;
    uint8_t* img = prx_image_load_file("spujobs/out/SPUJOBS_image.bin", &size);
    if (!img) { fprintf(stderr, "[mm] no SPUJobs image -- module load will fail\n"); return; }
    prx_module m; memset(&m, 0, sizeof m);
    m.name = "SPUJobs"; m.base = MM_SPUJOBS_BASE; m.image = img; m.image_size = size;
    m.funcs = (const prx_func_entry*)spujobs_function_table; m.func_count = spujobs_function_table_count;
    const prx_load_result r = prx_load_module(&m, mm_register);
    s_spujobs_loaded = r.ok;
    fprintf(stderr, "[mm] SPUJobs image: ok=%d size=%u funcs=%u\n", r.ok, size, r.funcs_registered);
    free(img);
}
extern "C" void ps3_load_prx_modules(void)
{
    mm_load_spujobs();
    const char* path = getenv("MM_LIBSRE_IMAGE");
    if (!path || !*path) path = "fw/out/libsre_image.bin";

    uint32_t size = 0;
    uint8_t* img = prx_image_load_file(path, &size);
    if (!img) {
        fprintf(stderr, "[mm] no libsre image at %s -- staying on HLE SPURS\n", path);
        return;
    }

    prx_module m;
    memset(&m, 0, sizeof m);
    m.name         = "libsre";
    m.base         = LIBSRE_BASE;
    m.image        = img;
    m.image_size   = size;
    m.funcs        = (const prx_func_entry*)libsre_function_table;
    m.func_count   = libsre_function_table_count;
    m.exports      = k_exports;
    m.export_count = k_export_n;

    const prx_load_result r = prx_load_module(&m, mm_register);
    if (!r.ok) return;

    /* libsre's own imports go to the HLE. When the lift was given --hle-stubs
     * the stubs already call ps3_hle_call and this patching is unused; it
     * covers a lift that kept the literal stubs, which load an OPD pointer and
     * branch through it. */
    uint32_t patched = 0;
    for (uint32_t i = 0; i < k_import_n; i++) {
        const uint32_t opd  = MM_BRIDGE_OPD  + i * 8u;
        const uint32_t code = MM_BRIDGE_CODE + i * 4u;
        const uint32_t slot = k_imports[i].slot;
        be32w(opd, code);
        be32w(opd + 4u, LIBSRE_TOC);
        ppu_register_function(code, mm_libsre_import_bridge);
        if (be32r(vm_base + slot) != 0x39800000u) { be32w(slot, opd); patched++; }
        for (uint32_t off = 0; off + 4u <= size; off += 4u)
            if (be32r(vm_base + LIBSRE_BASE + off) == slot) { be32w(LIBSRE_BASE + off, opd); patched++; }
    }
    fprintf(stderr, "[mm] libsre loaded: %u exports, %u imports bridged (%u words patched)\n",
            k_export_n, k_import_n, patched);
    free(img);
}

/* ---- stall watchdog: MM_WATCHDOG=<seconds> reports what every guest thread is doing ---- */
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
extern "C" const char* g_hle_inflight[64];
extern "C" void ppu_report_guest_lrs(void);
static void mm_peek(void)
{
    const char* e = getenv("MM_PEEK");
    if (!e || !*e) return;
    char buf[512]; strncpy(buf, e, sizeof buf - 1); buf[sizeof buf - 1] = 0;
    for (char* tok = strtok(buf, ","); tok; tok = strtok(NULL, ",")) {
        const uint32_t ea = (uint32_t)strtoul(tok, NULL, 16);
        for (uint32_t k = 0; k < 128u; k += 32u) {
            fprintf(stderr, "[MMPEEK] %08X:", ea + k);
            for (uint32_t j = 0; j < 32u; j += 4u) fprintf(stderr, " %08X", be32r(vm_base + ea + k + j));
            fprintf(stderr, "\n");
        }
    }
}
/* MM_HWWATCH=<hexEA>: hardware write watchpoint (DR0, 8 bytes) on every thread,
 * re-armed every 2 s for new threads. The VEH names the writing thread and its
 * host backtrace as RVAs (symbolize against MyGameRecomp.pdb). */
#include <tlhelp32.h>
extern "C" volatile uint32_t g_mm_hw_target;
static uintptr_t s_hw_host = 0;
static volatile LONG s_hw_hits = 0;
static volatile int s_hw_disarm = 0;
static char s_hw_buf[2048];
static LONG WINAPI mm_hw_veh(EXCEPTION_POINTERS* ep)
{
    if (ep->ExceptionRecord->ExceptionCode != 0x80000004u) return EXCEPTION_CONTINUE_SEARCH;
    if (!(ep->ContextRecord->Dr6 & 1)) return EXCEPTION_CONTINUE_SEARCH;
    ep->ContextRecord->Dr6 = 0;
    LONG k = InterlockedIncrement(&s_hw_hits);
    if (k > 40) { s_hw_disarm = 1; ep->ContextRecord->Dr7 &= ~0xF0003ull; return EXCEPTION_CONTINUE_EXECUTION; }
    {
        void* fr[24]; USHORT n = RtlCaptureStackBackTrace(0, 24, fr, NULL);
        ULONG_PTR base = (ULONG_PTR)GetModuleHandleA(NULL);
        PWSTR wn = NULL;
        typedef HRESULT (WINAPI *gtd_fn)(HANDLE, PWSTR*);
        static gtd_fn gtd = (gtd_fn)(void*)GetProcAddress(GetModuleHandleA("kernel32.dll"), "GetThreadDescription");
        if (gtd) gtd(GetCurrentThread(), &wn);
        int o = snprintf(s_hw_buf, sizeof s_hw_buf, "[mm-hw] #%ld write to watched ea, thread \"", k);
        for (int i = 0; wn && wn[i] && i < 40; i++) s_hw_buf[o++] = (char)wn[i];
        o += snprintf(s_hw_buf + o, sizeof s_hw_buf - o, "\" rip=0x%llX now=%08X %08X rvas:",
                      (unsigned long long)(ep->ContextRecord->Rip - base),
                      be32r(vm_base + (uint32_t)(s_hw_host - (uintptr_t)vm_base)),
                      be32r(vm_base + (uint32_t)(s_hw_host - (uintptr_t)vm_base) + 4));
        for (USHORT i = 0; i < n && o < (int)sizeof s_hw_buf - 20; i++)
            o += snprintf(s_hw_buf + o, sizeof s_hw_buf - o, " %llX", (unsigned long long)((ULONG_PTR)fr[i] - base));
        s_hw_buf[o++] = '\n'; { DWORD wr; WriteFile(GetStdHandle(STD_ERROR_HANDLE), s_hw_buf, (DWORD)o, &wr, NULL); }
        if (wn) LocalFree(wn);
    }
    return EXCEPTION_CONTINUE_EXECUTION;
}
static void mm_hw_arm_all(void)
{
    const DWORD me = GetCurrentThreadId(), pid = GetCurrentProcessId();
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
    if (snap == INVALID_HANDLE_VALUE) return;
    THREADENTRY32 te; te.dwSize = sizeof te;
    for (BOOL ok = Thread32First(snap, &te); ok; ok = Thread32Next(snap, &te)) {
        if (te.th32OwnerProcessID != pid || te.th32ThreadID == me) continue;
        HANDLE h = OpenThread(THREAD_GET_CONTEXT | THREAD_SET_CONTEXT | THREAD_SUSPEND_RESUME, FALSE, te.th32ThreadID);
        if (!h) continue;
        if (SuspendThread(h) != (DWORD)-1) {
            CONTEXT c; memset(&c, 0, sizeof c); c.ContextFlags = CONTEXT_DEBUG_REGISTERS;
            if (GetThreadContext(h, &c) && c.Dr0 != s_hw_host) {
                c.Dr0 = s_hw_host;
                c.Dr7 = (c.Dr7 & ~0xF0003ull) | 1ull | (1ull << 16) | (3ull << 18);   /* L0, write, 8 bytes */
                SetThreadContext(h, &c);
            }
            ResumeThread(h);
        }
        CloseHandle(h);
    }
    CloseHandle(snap);
}
static DWORD WINAPI mm_hw_thread(LPVOID p)
{
    uint32_t ea = (uint32_t)(uintptr_t)p & ~7u;
    { DWORD wr; const char m[] = "[mm-hw] thread started\n"; WriteFile(GetStdHandle(STD_ERROR_HANDLE), m, sizeof m - 1, &wr, NULL); }
    while (!vm_base) Sleep(50);
    Sleep(20000);
    if (!ea) { while (!g_mm_hw_target) Sleep(20); ea = g_mm_hw_target & ~7u; Sleep(500); }
    s_hw_host = (uintptr_t)(vm_base + ea);
    AddVectoredExceptionHandler(1, mm_hw_veh);
    { char b[96]; int n = snprintf(b, sizeof b, "[mm-hw] watching guest 0x%08X (host %p)\n", ea, (void*)s_hw_host);
      DWORD wr; WriteFile(GetStdHandle(STD_ERROR_HANDLE), b, (DWORD)n, &wr, NULL); }
    for (;;) { if (!s_hw_disarm) mm_hw_arm_all(); Sleep(2000); }
}
static struct MmHwStart {
    MmHwStart() {
        const char* e = getenv("MM_HWWATCH");
        if (e && *e) CreateThread(NULL, 0, mm_hw_thread, (LPVOID)(uintptr_t)strtoul(e, 0, 16), 0, NULL);
        else if (getenv("MM_HWWATCH_FONT")) CreateThread(NULL, 0, mm_hw_thread, (LPVOID)0, 0, NULL);
    }
} s_mm_hw_start;
/* MM_WATCH=<hexEA>: poll 32 bytes every ms; on change print old/new and every thread's lr. */
static DWORD WINAPI mm_watch_thread(LPVOID p)
{
    const uint32_t ea = (uint32_t)(uintptr_t)p;
    uint32_t prev[8], cur[8]; int n = 0;
    while (!vm_base) Sleep(50);
    Sleep(20000);   /* skip boot */
    for (int i = 0; i < 8; i++) prev[i] = be32r(vm_base + ea + 4u * i);
    for (;;) {
        Sleep(1);
        int ch = 0;
        for (int i = 0; i < 8; i++) { cur[i] = be32r(vm_base + ea + 4u * i); if (cur[i] != prev[i] && i != 4 && i != 7) ch = 1; }
        if (ch && n < 40) {
            n++;
            fprintf(stderr, "[mm-watch] %08X changed:", ea);
            for (int i = 0; i < 8; i++) fprintf(stderr, " %08X>%08X", prev[i], cur[i]);
            fprintf(stderr, "\n");
            ppu_report_guest_lrs();
        }
        memcpy(prev, cur, sizeof prev);
    }
}
static struct MmWatchStart {
    MmWatchStart() {
        const char* e = getenv("MM_WATCH");
        if (e && *e) CreateThread(NULL, 0, mm_watch_thread, (LPVOID)(uintptr_t)strtoul(e, 0, 16), 0, NULL);
    }
} s_mm_watch_start;
static DWORD WINAPI mm_watchdog(LPVOID p)
{
    const DWORD period = (DWORD)(uintptr_t)p * 1000u;
    const DWORD t0 = GetTickCount();
    for (;;) {
        Sleep(period);
        fprintf(stderr, "[MMWD] ---- t=%lus ----\n", (unsigned long)((GetTickCount() - t0) / 1000u));
        for (unsigned t = 0; t < 64u; t++)
            if (g_hle_inflight[t]) fprintf(stderr, "[MMWD]   guest-tid %-3u inside %s\n", t, g_hle_inflight[t]);
        ppu_report_guest_lrs(); mm_peek();
    }
}
static struct MmWatchdogStart {
    MmWatchdogStart() {
        const char* e = getenv("MM_WATCHDOG");
        const int s = e ? atoi(e) : 0;
        if (s > 0) CreateThread(NULL, 0, mm_watchdog, (LPVOID)(uintptr_t)s, 0, NULL);
    }
} s_mm_watchdog_start;
#endif
