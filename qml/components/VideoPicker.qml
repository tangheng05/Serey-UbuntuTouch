import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3 as Popups
import Lomiri.Content 1.3
import "../Theme"

Popups.PopupBase {
    id: picker
    objectName: "videoPickerDialog"

    parent: QuickUtils.rootItem(picker)
    anchors.fill: parent

    property var activeTransfer
    signal picked(string fileUrl)
    signal cancelled()

    Rectangle {
        anchors.fill: parent
        color: Style.surface

        ContentTransferHint {
            anchors.fill: parent
            activeTransfer: picker.activeTransfer
        }

        ContentPeerPicker {
            id: peerPicker
            anchors.fill: parent
            visible: true
            contentType: ContentType.Videos
            handler: ContentHandler.Source

            onPeerSelected: {
                peer.selectionType = ContentTransfer.Single;
                picker.activeTransfer = peer.request();
                stateChangeConnection.target = picker.activeTransfer;
            }
            onCancelPressed: {
                picker.cancelled();
                Popups.PopupUtils.close(picker);
            }
        }
    }

    Connections {
        id: stateChangeConnection
        target: null
        onStateChanged: {
            var t = picker.activeTransfer;
            if (!t)
                return;
            if (t.state === ContentTransfer.Charged) {
                if (t.items.length > 0)
                    picker.picked(String(t.items[0].url));
                Popups.PopupUtils.close(picker);
            } else if (t.state === ContentTransfer.Aborted) {
                picker.cancelled();
                Popups.PopupUtils.close(picker);
            }
        }
    }

    Component.onCompleted: show()
}
