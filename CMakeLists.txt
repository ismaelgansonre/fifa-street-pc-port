# fifastreet - ReXGlue Recompiled Project (macOS, SDK prébuildé immuable)
#
# SDK boilerplate lives in generated/rexglue.cmake.
# Toutes les adaptations macOS vivent ICI (projet), jamais dans le SDK.

cmake_minimum_required(VERSION 3.25)
project(fifastreet LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(generated/rexglue.cmake)

# Sources
set(FIFASTREET_SOURCES
    src/main.cpp
)

add_executable(fifastreet ${FIFASTREET_SOURCES})

# GPU_PLUGINS xenos : sans cela aucune dylib de renderer n'est stagée (audit J0).
rexglue_setup_target(fifastreet GPU_PLUGINS xenos)

# The source SDK keeps ImGui private to rexruntime; its public UI headers
# still require the include directory when compiling the host application.
if(TARGET imgui::imgui)
    target_include_directories(fifastreet PRIVATE
        $<TARGET_PROPERTY:imgui::imgui,INTERFACE_INCLUDE_DIRECTORIES>)
endif()

# --- Optimisation guest (Apple Silicon) -------------------------------------
# -mcpu=apple-m1 -O3 sur le code recompilé : perf + mitigation principale de
# la course au démarrage (10/10 boots propres en octobre). L'hôte reste -O2.
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(fifastreet PRIVATE -O2)
    if(TARGET fifastreet_recomp)
        target_compile_options(fifastreet_recomp PRIVATE -O3 -mcpu=apple-m1)
    endif()
endif()

# FIFA Street DLL-specific kernel stubs (récupérés d'octobre, 69d231b).
if(TARGET fifastreet_fifadllzf_xex)
    if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
        target_compile_options(fifastreet_fifadllzf_xex PRIVATE -O3 -mcpu=apple-m1)
    endif()
    target_sources(fifastreet_fifadllzf_xex PRIVATE
        src/stubs.cpp
        src/native_libc_hooks.cpp
    )
endif()

# World Tour competition engine DLL. Optimisé, sans les stubs fifadllzf.
# (deux orthographes possibles selon la casse d'out_directory_path)
foreach(_fce_target fifastreet_footballcompengzf_xex fifastreet_FootballCompEngzf_xex)
    if(TARGET ${_fce_target})
        if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
            target_compile_options(${_fce_target} PRIVATE -O3 -mcpu=apple-m1)
        endif()
    endif()
endforeach()

# --- MACOS-PORT-O1-MEGA-TU (octobre, commit 69d231b) ------------------------
# Les TU d'enregistrement générés défient les choix par défaut d'Apple clang :
# - register.cpp appelle registrar->SetFunction une fois par fonction guest.
#   Sans les barrières du fork d'octobre (SDK immuable désormais), -O0 suffit :
#   rien n'est réordonné/fusionné, et le TU 159k lignes compile en secondes.
# - -fno-global-isel évite le Localizer GlobalISel quadratique (15-60+ min).
# - init.cpp = tables statiques géantes : -O1 en secondes.
if(APPLE)
    set_source_files_properties("${CMAKE_CURRENT_SOURCE_DIR}/generated/default/fifastreet_register.cpp"
        PROPERTIES COMPILE_OPTIONS "-fno-global-isel")
    set_source_files_properties("${CMAKE_CURRENT_SOURCE_DIR}/generated/fifadllzf_xex/fifastreet_register.cpp"
        PROPERTIES COMPILE_OPTIONS "-O0;-g0;-fno-global-isel" SKIP_PRECOMPILE_HEADERS ON)
    set_source_files_properties("${CMAKE_CURRENT_SOURCE_DIR}/generated/fifadllzf_xex/fifastreet_init.cpp"
        PROPERTIES COMPILE_OPTIONS "-O1;-g0")
endif()
# END MACOS-PORT-O1-MEGA-TU

# --- Chargement des modules guest (contournement dlopen, audit J0) ----------
# Le registre demande un nom NU ("fifastreet_fifadllzf_xex", ni préfixe lib
# ni .dylib) : dlopen macOS ne le résout pas seul. On copie la dylib sous ce
# nom exact à côté de l'exécutable ; le launcher exportera
# DYLD_LIBRARY_PATH=<exe_dir> (J4).
foreach(_mod_target fifastreet_fifadllzf_xex fifastreet_footballcompengzf_xex fifastreet_FootballCompEngzf_xex)
    if(TARGET ${_mod_target})
        add_custom_command(TARGET ${_mod_target} POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "$<TARGET_FILE:${_mod_target}>"
                "$<TARGET_FILE_DIR:fifastreet>/$<TARGET_FILE_BASE_NAME:${_mod_target}>"
            COMMAND ${CMAKE_COMMAND} -E make_directory
                "$<TARGET_FILE_DIR:fifastreet>/vulkan"
            COMMENT "Bare-name module copy: ${_mod_target}")
    endif()
endforeach()
