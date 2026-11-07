# Microsoft Detours as a static ARM64EC library, with the flags of its own
# src/Makefile (DETOURS_TARGET_PROCESSOR=ARM64EC). /Zl keeps the objects
# CRT-neutral, like the official build.
cmake_minimum_required(VERSION 3.25)
project(detours CXX)
set(DETOURS_SRC "" CACHE PATH "microsoft/Detours checkout")
set(S "${DETOURS_SRC}/src")
add_library(detours STATIC
  ${S}/detours.cpp ${S}/modules.cpp ${S}/disasm.cpp ${S}/image.cpp ${S}/creatwth.cpp
  ${S}/disolx86.cpp ${S}/disolx64.cpp ${S}/disolia64.cpp ${S}/disolarm.cpp ${S}/disolarm64.cpp)
target_compile_definitions(detours PRIVATE DETOUR_DEBUG=0 WIN32_LEAN_AND_MEAN _WIN32_WINNT=0x501)
target_compile_options(detours PRIVATE /W3 /Gy /Zl /O1 -Wno-everything)
install(TARGETS detours ARCHIVE DESTINATION lib)
install(FILES ${S}/detours.h ${S}/detver.h DESTINATION include/detours)
