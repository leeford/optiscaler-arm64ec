# Cross-compile Windows ARM64EC binaries on Linux with clang-cl + lld-link,
# against the MSVC CRT and Windows SDK unpacked by xwin (winsysroot layout).
#
#   -DCMAKE_TOOLCHAIN_FILE=cmake/toolchain-clangcl-arm64ec.cmake
#   -DXWIN_SYSROOT=/path/to/sysroot     (or env XWIN_SYSROOT)
#   -DLLVM_SUFFIX=-22                   (or env LLVM_SUFFIX; "" for unversioned)

set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_VERSION 10.0)
set(CMAKE_SYSTEM_PROCESSOR ARM64EC)

if(NOT DEFINED XWIN_SYSROOT)
  set(XWIN_SYSROOT "$ENV{XWIN_SYSROOT}")
endif()
if(NOT XWIN_SYSROOT OR NOT EXISTS "${XWIN_SYSROOT}/VC/Tools/MSVC")
  message(FATAL_ERROR "XWIN_SYSROOT must point at an xwin --use-winsysroot-style splat")
endif()
if(NOT DEFINED LLVM_SUFFIX)
  if(DEFINED ENV{LLVM_SUFFIX})
    set(LLVM_SUFFIX "$ENV{LLVM_SUFFIX}")
  else()
    set(LLVM_SUFFIX "")
  endif()
endif()
# try_compile() runs in a fresh project and needs these passed through.
list(APPEND CMAKE_TRY_COMPILE_PLATFORM_VARIABLES XWIN_SYSROOT LLVM_SUFFIX)

set(CMAKE_C_COMPILER   "clang-cl${LLVM_SUFFIX}")
set(CMAKE_CXX_COMPILER "clang-cl${LLVM_SUFFIX}")
set(CMAKE_LINKER       "lld-link${LLVM_SUFFIX}")
set(CMAKE_AR           "llvm-lib${LLVM_SUFFIX}")
set(CMAKE_RC_COMPILER  "llvm-rc${LLVM_SUFFIX}")
set(CMAKE_MT           "llvm-mt${LLVM_SUFFIX}")
set(CMAKE_C_COMPILER_TARGET   arm64ec-pc-windows-msvc)
set(CMAKE_CXX_COMPILER_TARGET arm64ec-pc-windows-msvc)

# The SDK version directory, e.g. 10.0.26100.
file(GLOB _sdk_dirs LIST_DIRECTORIES true "${XWIN_SYSROOT}/Windows Kits/10/Lib/*")
list(SORT _sdk_dirs)
list(GET _sdk_dirs -1 _sdk_dir)
get_filename_component(XWIN_SDK_VERSION "${_sdk_dir}" NAME)
file(GLOB _msvc_dirs LIST_DIRECTORIES true "${XWIN_SYSROOT}/VC/Tools/MSVC/*")
list(SORT _msvc_dirs)
list(GET _msvc_dirs -1 XWIN_MSVC_DIR)

set(_common "/winsysroot \"${XWIN_SYSROOT}\" -Wno-unused-command-line-argument")
set(CMAKE_C_FLAGS_INIT   "${_common}")
set(CMAKE_CXX_FLAGS_INIT "${_common}")

# The ARM64 SDK import libraries are ARM64X except the UCRT one, which only has
# ARM64 entries. setup-toolchain.sh generates an ARM64EC UCRT import library
# (scripts/make-ucrt-arm64ec.py) next to it; link that instead.
set(XWIN_UCRT_EC "${XWIN_SYSROOT}/Windows Kits/10/Lib/${XWIN_SDK_VERSION}/ucrt/arm64ec/ucrt.lib")
if(NOT EXISTS "${XWIN_UCRT_EC}")
  message(FATAL_ERROR "${XWIN_UCRT_EC} is missing; run scripts/setup-toolchain.sh")
endif()
set(_link "/machine:arm64ec /winsysroot:\"${XWIN_SYSROOT}\" /nodefaultlib:ucrt.lib \"${XWIN_UCRT_EC}\"")
set(CMAKE_EXE_LINKER_FLAGS_INIT    "${_link}")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "${_link}")
set(CMAKE_MODULE_LINKER_FLAGS_INIT "${_link}")

# llvm-rc needs the SDK headers for winres.h etc.
set(CMAKE_RC_FLAGS_INIT
  "/I \"${XWIN_SYSROOT}/Windows Kits/10/Include/${XWIN_SDK_VERSION}/um\" /I \"${XWIN_SYSROOT}/Windows Kits/10/Include/${XWIN_SDK_VERSION}/shared\" /I \"${XWIN_MSVC_DIR}/include\"")

set(CMAKE_MSVC_RUNTIME_LIBRARY MultiThreadedDLL)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)

# xwin ships only the release CRT, so compiler checks must not pick Debug.
set(CMAKE_TRY_COMPILE_CONFIGURATION Release)
