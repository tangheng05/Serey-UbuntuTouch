pragma Singleton
import QtQuick 2.7

QtObject {
    id: toast

    property string message: ""
    property bool isError: false
    property int seq: 0

    function show(msg) { message = msg; isError = false; seq++; }
    function success(msg) { message = msg; isError = false; seq++; }
    function error(msg) { message = msg; isError = true; seq++; }
}
