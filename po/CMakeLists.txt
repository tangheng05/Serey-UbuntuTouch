set(DOMAIN serey.serey-io)
set(POT_FILE ${DOMAIN}.pot)
file(GLOB PO_FILES *.po)

find_program(INTLTOOL_MERGE intltool-merge)
find_program(GETTEXT_MSGFMT msgfmt)

# Compile each .po into a .mo installed under the standard locale tree.
foreach(PO_FILE ${PO_FILES})
    get_filename_component(LANG ${PO_FILE} NAME_WE)
    if(GETTEXT_MSGFMT)
        set(MO_FILE ${CMAKE_CURRENT_BINARY_DIR}/${LANG}.mo)
        add_custom_command(OUTPUT ${MO_FILE}
            COMMAND ${GETTEXT_MSGFMT} ${PO_FILE} -o ${MO_FILE}
            DEPENDS ${PO_FILE})
        install(FILES ${MO_FILE}
            DESTINATION ${CMAKE_INSTALL_PREFIX}/share/locale/${LANG}/LC_MESSAGES
            RENAME ${DOMAIN}.mo)
        list(APPEND MO_FILES ${MO_FILE})
    endif()
endforeach()

add_custom_target(translations ALL DEPENDS ${MO_FILES})
