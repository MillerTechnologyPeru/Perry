# Included after MapLibre Native's project() (CMAKE_PROJECT_INCLUDE): adds
# libPerryMapLibre.so once MapLibre's own targets are defined. The deferred
# call's arguments expand when it runs, in MapLibre's directory, so this
# file's directory is written into it now.
include_guard(GLOBAL)
cmake_language(EVAL CODE
    "cmake_language(DEFER DIRECTORY \"${CMAKE_SOURCE_DIR}\" CALL include \"${CMAKE_CURRENT_LIST_DIR}/targets.cmake\")")
