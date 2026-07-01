pragma Singleton
import QtQuick 2.7
import "../services/Translations.js" as Translations

/*
 * Reactive translation wrapper. All Lang.tr() bindings track _rev, so when
 * the language changes _rev is bumped and every binding re-evaluates —
 * giving instant in-app language switching without restarting.
 *
 * Translations are looked up from Translations.js (a plain JS object) rather
 * than gettext/.mo files — gettext caches its message catalog at the C level
 * and cannot be reliably reloaded at runtime without a process restart.
 */
Item {
    id: lang
    property int _rev: 0

    Component.onCompleted: {
        Session.languageChanged.connect(function() {
            lang._rev = lang._rev + 1;
        });
    }

    function tr(str) {
        void(_rev);          // makes QML track _rev as a binding dependency
        return Translations.tr(str, Session.language);
    }
}
