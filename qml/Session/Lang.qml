pragma Singleton
import QtQuick 2.7
import "../services/Translations.js" as Translations

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
