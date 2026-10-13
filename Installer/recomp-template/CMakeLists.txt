# fifastreet - ReXGlue Recompiled Project
#
# SDK boilerplate lives in generated/rexglue.cmake.

cmake_minimum_required(VERSION 3.25)
project(fifastreet LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(generated/rexglue.cmake)

# Sources
set(FIFASTREET_SOURCES
    src/main.cpp
)

if(WIN32)
    enable_language(RC)
    add_executable(fifastreet WIN32 ${FIFASTREET_SOURCES})
    target_sources(fifastreet PRIVATE src/fifastreet.rc)

    if(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
        set_source_files_properties(src/fifastreet.rc PROPERTIES
            COMPILE_OPTIONS "/nologo"
        )
        target_include_directories(fifastreet PRIVATE
            "${CMAKE_CURRENT_SOURCE_DIR}/src"
        )
    endif()
else()
    add_executable(fifastreet ${FIFASTREET_SOURCES})
endif()

rexglue_setup_target(fifastreet GPU_PLUGINS xenos)
target_include_directories(fifastreet PRIVATE src)

# The source SDK keeps ImGui private to rexruntime; its public UI headers
# still require the include directory when compiling the host application.
# Propagate headers only, keeping the ImGui objects in the shared runtime.
if(TARGET imgui::imgui)
    target_include_directories(fifastreet PRIVATE
        $<TARGET_PROPERTY:imgui::imgui,INTERFACE_INCLUDE_DIRECTORIES>)
endif()

# Guest SIMD code must be optimized even when using the debug runtime. Keep
# debug symbols and checked runtime libraries while avoiding unoptimized SIMD
# wrappers in the game and its separately compiled DLL.
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(fifastreet PRIVATE -O2)
    if(TARGET fifastreet_recomp)
        target_compile_options(fifastreet_recomp PRIVATE -O2)
    endif()
endif()

# FIFA Street DLL-specific kernel stubs.
if(TARGET fifastreet_fifadllzf_xex)
    if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
        target_compile_options(fifastreet_fifadllzf_xex PRIVATE -O2)
    endif()
    target_sources(fifastreet_fifadllzf_xex PRIVATE
        src/stubs.cpp
        src/native_libc_hooks.cpp
    )
endif()

# World Tour competition engine DLL. Keep it optimized, but do not attach
# fifadllzf-specific stubs to this independent guest module.
if(TARGET fifastreet_FootballCompEngzf_xex)
    if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
        target_compile_options(fifastreet_FootballCompEngzf_xex PRIVATE -O2)
    endif()
endif()

# MACOS-PORT-O1-MEGA-TU (auto-added by the macOS port effort; safe to remove)
# The generated function-registration units defeat Apple clang's default
# backend choices, in two different ways:
# - register.cpp (one per module) calls registrar->SetFunction once per guest
#   function. Codegen barriers (see patches/rexglue-macos-addendum.patch) keep
#   each call in its own basic block, but Apple clang still routes these TUs
#   through GlobalISel, whose Localizer pass spends 15-60+ minutes (single
#   core) on them. -fno-global-isel selects the regular SelectionDAG/FastISel
#   path: seconds. The functions run once at module load, so this is purely a
#   compile-time fix.
# - the fifadllzf register TU is ~159k lines; it additionally compiles at
#   -O0/-g0 and skips the PCH (the shared PCH is built optimized, and clang
#   rejects it for an -O0 TU). The file only includes two small headers.
# - init.cpp files are giant static data tables; -O1 compiles them in seconds.
# Guest code (recomp.NNN files) and all other modules keep their normal
# optimization.
if(APPLE)
    set_source_files_properties("${CMAKE_CURRENT_SOURCE_DIR}/generated/default/fifastreet_register.cpp"
        PROPERTIES COMPILE_OPTIONS "-fno-global-isel")
    set_source_files_properties("${CMAKE_CURRENT_SOURCE_DIR}/generated/fifadllzf_xex/fifastreet_register.cpp"
        PROPERTIES COMPILE_OPTIONS "-O0;-g0;-fno-global-isel" SKIP_PRECOMPILE_HEADERS ON)
    set_source_files_properties("${CMAKE_CURRENT_SOURCE_DIR}/generated/fifadllzf_xex/fifastreet_init.cpp"
        PROPERTIES COMPILE_OPTIONS "-O1;-g0")
endif()
# END MACOS-PORT-O1-MEGA-TU

# APPLE-GUEST-TUNING (Apple Silicon only)
# The guest hot path otherwise compiles for generic armv8-a. Apple scheduling
# plus -O3 help the recompiled PowerPC code on Apple Silicon (measured on the
# FIFA Street port, 2026-10-13). Later flags win, so -O3 here overrides the
# target-level -O2 above; guest FP semantics stay IEEE (no unsafe math).
if(APPLE)
    foreach(_rex_guest_target fifastreet_recomp fifastreet_fifadllzf_xex fifastreet_FootballCompEngzf_xex)
        if(TARGET ${_rex_guest_target})
            target_compile_options(${_rex_guest_target} PRIVATE -mcpu=apple-m1 -O3)
        endif()
    endforeach()
endif()
