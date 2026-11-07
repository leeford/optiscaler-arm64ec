/* The Windows SDK's DirectXMath.h includes <cpuid.h> whenever clang defines
   __x86_64__, which clang also does for ARM64EC (as MSVC defines _M_X64).
   clang's cpuid.h is x86 inline asm, so give ARM64EC an empty one. */
#pragma once
#if !defined(__arm64ec__)
#include_next <cpuid.h>
#endif
