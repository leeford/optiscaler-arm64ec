# OptiScaler ARM64EC build for clang-cl + lld-link (see toolchain-clangcl-arm64ec.cmake).
#
# Mirrors the Release|ARM64EC configuration of OptiScaler/OptiScaler.vcxproj.
# Sources are globbed so files added upstream are picked up without edits here;
# anything the vcxproj does not compile goes in OPTI_EXCLUDE below.
#
#   cmake -S cmake -B out -G Ninja -DCMAKE_TOOLCHAIN_FILE=cmake/toolchain-clangcl-arm64ec.cmake \
#         -DOPTI_SRC=/path/to/patched/OptiScaler -DOPTI_DEPS=/path/to/deps/prefix
cmake_minimum_required(VERSION 3.25)
project(OptiScalerArm64ec C CXX RC)

set(OPTI_SRC "" CACHE PATH "Root of the patched OptiScaler checkout")
set(OPTI_DEPS "" CACHE PATH "Prefix with the ARM64EC dependency libraries (lib/, include/)")
set(OPTI_FXC "${CMAKE_CURRENT_LIST_DIR}/../scripts/fxc.sh" CACHE FILEPATH "fxc wrapper")
set(OPTI_BUILD_COMMIT "unknown" CACHE STRING "Commit stamped into the DLL")
if(NOT EXISTS "${OPTI_SRC}/OptiScaler/OptiScaler.vcxproj")
  message(FATAL_ERROR "OPTI_SRC=${OPTI_SRC} is not an OptiScaler checkout")
endif()

set(P "${OPTI_SRC}/OptiScaler")
set(E "${OPTI_SRC}/external")

# --- sources -----------------------------------------------------------------
file(GLOB_RECURSE OPTI_SOURCES CONFIGURE_DEPENDS "${P}/*.cpp" "${P}/*.c")
set(OPTI_EXCLUDE
  "${P}/include/imgui/imgui_demo.cpp"   # excluded in the vcxproj too
)
list(REMOVE_ITEM OPTI_SOURCES ${OPTI_EXCLUDE})

# --- SGSR HLSL -> DXBC headers (FxCompile items in the vcxproj) --------------
set(GEN "${CMAKE_BINARY_DIR}/gen")
set(SHADER_HEADERS "")
foreach(spec
    "sgsr1/shaders/sgsr1_upscale.hlsl|sgsr1_upscale_cso"
    "sgsr2/shaders/sgsr2_convert.hlsl|sgsr2_convert_cso"
    "sgsr2/shaders/sgsr2_upscale.hlsl|sgsr2_upscale_cso")
  string(REPLACE "|" ";" spec "${spec}")
  list(GET spec 0 hlsl)
  list(GET spec 1 var)
  set(in "${P}/upscalers/${hlsl}")
  if(NOT EXISTS "${in}")
    continue()
  endif()
  get_filename_component(sdir "${in}" DIRECTORY)
  file(GLOB deps "${sdir}/*.hlsli")
  set(out "${GEN}/generated/${var}.h")
  add_custom_command(OUTPUT "${out}"
    COMMAND "${OPTI_FXC}" /nologo /T cs_5_0 /E CSMain /O3 /Vn "${var}" /Fh "${out}" "${in}"
    DEPENDS "${in}" ${deps}
    COMMENT "fxc ${hlsl}" VERBATIM)
  list(APPEND SHADER_HEADERS "${out}")
endforeach()
add_custom_target(opti_shaders DEPENDS ${SHADER_HEADERS})

# --- resource script (UTF-16 in the repo, llvm-rc wants UTF-8) ---------------
file(MAKE_DIRECTORY "${GEN}")
file(WRITE "${GEN}/resource_build_commit.h" "#define VER_BUILD_COMMIT \"${OPTI_BUILD_COMMIT}\"\n")
string(TIMESTAMP _date "%Y%m%d_%H%M%S" UTC)
file(WRITE "${GEN}/resource_build_date.h" "#define VER_BUILD_DATE \"${_date}\"\n")
add_custom_command(OUTPUT "${GEN}/OptiScaler.utf8.rc"
  COMMAND sh -c "iconv -f UTF-16 -t UTF-8 \"$0\" | sed '1s/^\\xEF\\xBB\\xBF//' > \"$1\"" "${P}/OptiScaler.rc" "${GEN}/OptiScaler.utf8.rc"
  DEPENDS "${P}/OptiScaler.rc" VERBATIM)

# --- the proxy DLL -------------------------------------------------------------
# Objects first, so the exports in Source.def can be resolved against them.
add_library(opti_objs OBJECT ${OPTI_SOURCES})
add_dependencies(opti_objs opti_shaders)

target_include_directories(opti_objs BEFORE PRIVATE
  "${CMAKE_CURRENT_LIST_DIR}/compat"
  "${GEN}"
  "${OPTI_DEPS}/include"
  "${P}" "${P}/include"
  "${E}/vulkan/include" "${E}/nvngx_dlss_sdk"
  "${E}/xess/inc/xess" "${E}/xess/inc/xell" "${E}/xess/inc/xess_fg"
  "${E}/FidelityFX-SDK/ffx-api/include/ffx_api"
  "${E}/simpleini" "${E}/unordered_dense/include" "${E}/spdlog/include"
  "${E}/freetype" "${E}/streamline" "${E}/streamline1" "${E}/nvapi"
  "${E}/nlohmann" "${E}/fakenvapi" "${E}/magic_enum/include/magic_enum"
  "${E}/AntiLag2-SDK" "${E}/latencyflex")

target_compile_definitions(opti_objs PRIVATE
  NDEBUG _DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR _WINDOWS _USRDLL _WINDLL
  UNICODE _UNICODE IMGUI_DISABLE_SSE)

target_compile_options(opti_objs PRIVATE
  $<$<COMPILE_LANGUAGE:CXX>:/std:c++latest>
  "$<$<COMPILE_LANGUAGE:CXX>:/FI${CMAKE_CURRENT_LIST_DIR}/compat/arm64ec_compat.h>"
  $<$<COMPILE_LANGUAGE:C,CXX>:/EHsc /O2 /Oi /Gy /GS /sdl /permissive- /fp:fast /W3 /Zc:__cplusplus>
  # MSVC-isms the code relies on that clang-cl warns about by default.
  $<$<COMPILE_LANGUAGE:C,CXX>:-Wno-microsoft -Wno-unused-parameter -Wno-unknown-pragmas
    -Wno-deprecated-declarations -Wno-missing-field-initializers -Wno-nonportable-include-path
    -Wno-invalid-offsetof -Wno-unused-variable -Wno-sign-compare -Wno-ignored-attributes
    -Wno-nan-infinity-disabled -Wno-unused-function -Wno-ignored-pragma-intrinsic
    -Wno-pragma-pack -Wno-unused-private-field -Wno-missing-braces -Wno-switch
    -Wno-c++11-narrowing -Wno-reorder-ctor -Wno-int-to-pointer-cast -Wno-cast-function-type-mismatch>)

# Source.def names C++ functions undecorated; lld-link needs the decorated names.
find_program(LLVM_NM NAMES "llvm-nm${LLVM_SUFFIX}" llvm-nm REQUIRED)
find_package(Python3 REQUIRED COMPONENTS Interpreter)
set(RESOLVED_DEF "${GEN}/OptiScaler.def")
add_custom_command(OUTPUT "${RESOLVED_DEF}"
  COMMAND Python3::Interpreter -I "${CMAKE_CURRENT_LIST_DIR}/../scripts/resolve-def.py"
          "${P}/Source.def" "${RESOLVED_DEF}" "${LLVM_NM}" $<TARGET_OBJECTS:opti_objs>
  DEPENDS opti_objs "${P}/Source.def" $<TARGET_OBJECTS:opti_objs>
  COMMAND_EXPAND_LISTS
  COMMENT "Resolving exports in Source.def" VERBATIM)
add_custom_target(opti_def DEPENDS "${RESOLVED_DEF}")

add_library(OptiScaler SHARED $<TARGET_OBJECTS:opti_objs> "${GEN}/OptiScaler.utf8.rc")
add_dependencies(OptiScaler opti_def)
set_target_properties(OptiScaler PROPERTIES OUTPUT_NAME OptiScaler PREFIX ""
  LINK_DEPENDS "${RESOLVED_DEF}")
set_source_files_properties("${GEN}/OptiScaler.utf8.rc" PROPERTIES
  COMPILE_DEFINITIONS OPTISCALER_BUILD_METADATA
  COMPILE_OPTIONS "/I;${P};/I;${GEN}")
target_link_options(OptiScaler PRIVATE "/DEF:${RESOLVED_DEF}")

target_link_directories(OptiScaler PRIVATE "${OPTI_DEPS}/lib")
target_link_libraries(OptiScaler PRIVATE
  # Lowercase: lld-link looks names up case-sensitively and xwin provides lowercase.
  winhttp windowsapp dbghelp dxgi d3d11 d3d12 vulkan-1 dxguid d3dcompiler delayimp
  freetype detours d3dx11
  ffx_fsr2_api_arm64ec ffx_fsr2_api_dx11_arm64ec ffx_fsr2_api_dx12_arm64ec ffx_fsr2_api_vk_arm64ec
  ffx_fsr2_212_api_dx12_arm64ec ffx_fsr2_212_api_vk_arm64ec ffx_fsr2_212_api_arm64ec
  ffx_backend_dx11_arm64ec ffx_fsr3_arm64ec ffx_fsr3upscaler_arm64ec
  ffx_opticalflow_arm64ec ffx_frameinterpolation_arm64ec)
target_link_options(OptiScaler PRIVATE
  /OPT:REF /OPT:ICF /INCREMENTAL:NO /SUBSYSTEM:WINDOWS
  /DELAYLOAD:vulkan-1.dll /DELAYLOAD:dxgi.dll /DELAYLOAD:d3d12.dll /DELAYLOAD:D3DCOMPILER_47.dll
  /ignore:4099 /ignore:4217)
