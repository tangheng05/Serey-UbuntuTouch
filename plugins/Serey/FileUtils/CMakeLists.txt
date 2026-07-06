set(PLUGIN sereyfileutils)

set(CMAKE_AUTOMOC ON)
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt5 REQUIRED COMPONENTS Core Qml)

add_library(${PLUGIN} MODULE
    plugin.cpp
    filechunkreader.cpp
    filechunkreader.h
)

target_link_libraries(${PLUGIN} Qt5::Core Qt5::Qml)

# lomiri-app-launch adds lib/<arch-triplet> to QML2_IMPORT_PATH for click
# packages, so installing under it makes `import Serey.FileUtils 1.0` resolve.
set(MODULE_DIR ${QT_IMPORTS_DIR}/Serey/FileUtils)

install(TARGETS ${PLUGIN} DESTINATION ${MODULE_DIR})
install(FILES qmldir DESTINATION ${MODULE_DIR})
