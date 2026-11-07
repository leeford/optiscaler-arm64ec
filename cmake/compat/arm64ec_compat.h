/* Force-included into every OptiScaler translation unit (/FI).
   MSVC lets ARM64EC code call a few x64 SSE intrinsics and maps them to ARM64
   ("softintrin"); clang-cl does not, so supply the ones OptiScaler uses. */
#pragma once
#if defined(__clang__) && defined(__arm64ec__) && defined(__cplusplus)
#include <intrin.h>
static __forceinline void _mm_pause(void) { __yield(); }
static __forceinline void _mm_sfence(void) { __dmb(_ARM64_BARRIER_ISHST); }
static __forceinline void _mm_lfence(void) { __dmb(_ARM64_BARRIER_ISHLD); }
static __forceinline void _mm_mfence(void) { __dmb(_ARM64_BARRIER_ISH); }
#endif
