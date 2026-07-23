cmake_minimum_required(VERSION 3.16)
project(serey)

# QML app with one compiled plugin (Serey.FileUtils, streaming file reads so
# large video uploads don't hold the whole file in RAM). We configure the
# manifest with the framework and architecture supplied by Clickable, build the
# plugin, then install the QML, assets and hooks into the click package root.

set(QT_IMPORTS_DIR "lib/${CMAKE_LIBRARY_ARCHITECTURE}")

set(APP_NAME serey)
set(DESKTOP_FILE "${APP_NAME}.desktop")
set(ICON_FILE assets/serey-logo.png)

# Fill @CLICK_FRAMEWORK@ / $ENV{...} placeholders in manifest.json.in -> manifest.json
configure_file(manifest.json.in ${CMAKE_CURRENT_BINARY_DIR}/manifest.json)
configure_file(push-helper.apparmor ${CMAKE_CURRENT_BINARY_DIR}/push-helper.apparmor)

install(FILES ${CMAKE_CURRENT_BINARY_DIR}/manifest.json
    DESTINATION ${CMAKE_INSTALL_PREFIX})
install(FILES ${APP_NAME}.apparmor
    DESTINATION ${CMAKE_INSTALL_PREFIX})
install(FILES ${DESKTOP_FILE}
    DESTINATION ${CMAKE_INSTALL_PREFIX})
install(FILES push-helper.json ${CMAKE_CURRENT_BINARY_DIR}/push-helper.apparmor
    DESTINATION ${CMAKE_INSTALL_PREFIX})
install(PROGRAMS push-helper
    DESTINATION ${CMAKE_INSTALL_PREFIX})

install(DIRECTORY qml
    DESTINATION ${CMAKE_INSTALL_PREFIX})
install(DIRECTORY assets
    DESTINATION ${CMAKE_INSTALL_PREFIX})

# C++ QML plugin: Serey.FileUtils (chunked file reads for video upload)
add_subdirectory(plugins/Serey/FileUtils)

# Translations
add_subdirectory(po)
