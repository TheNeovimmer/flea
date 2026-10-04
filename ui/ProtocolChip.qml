import QtQuick
import "." as Flea

// One protocol member: buttons A's one control as a set member (ButtonSystem040 callout 1, Nearby callout 6), current in the foreground frame.
Flea.DialogButton {
    id: root

    property bool picked: false

    setMember: true
    current: root.picked
    // The form owns the Tab order, so the member only reports it and is never walked by Qt.
    tabHandle: true

    function takeFocus() {
        root.forceActiveFocus()
    }
}
