# libPerryMapLibre.so: Perry's C interface over MapLibre Native's core,
# exporting only the pml_ functions.
add_library(PerryMapLibre SHARED "${CMAKE_CURRENT_LIST_DIR}/perry_maplibre.cpp")
target_link_libraries(PerryMapLibre PRIVATE mbgl-core)
set_target_properties(PerryMapLibre PROPERTIES CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON)
target_link_options(PerryMapLibre PRIVATE -Wl,--exclude-libs,ALL)
