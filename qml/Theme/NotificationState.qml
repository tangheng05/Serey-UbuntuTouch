pragma Singleton
import QtQuick 2.7

/*
 * Shared unread-notification count. Main.qml owns the polling/push logic and
 * writes `unread`; any page can read it to show a badge. Lives in a singleton
 * (not a Main.qml id) because pages pushed onto a PageStack are separately
 * compiled components and can't resolve the shell's ids — the old
 * `root.lastUnreadCount` reference silently never resolved from those pages.
 *
 * Sentinel: -1 means "not yet polled" (seeds silently, no notify); >= 0 is a
 * real count. Badges should test `unread > 0`.
 */
QtObject {
    id: state

    property int unread: -1
}
