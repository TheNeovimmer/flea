pragma Singleton

import Quickshell
import QtQuick

// The Settings boards' row geometry that CSS derives instead of stating. The boards are drawn at base-size 14, where bodySmall is 13 and the caption 12, so each figure scales with that token as Theme.settings.railPaddingY does.
Singleton {
    id: root

    // Tabs040.html data-flea="hint": padding 4px 14px 2px 42px, 12px type, line-height 1.5.
    readonly property int boardHintTop: 4
    readonly property int boardHintBottom: 2
    readonly property real boardHintLineRatio: 1.5
    readonly property int boardBodySmall: 13

    readonly property int hintTop: Math.round(root.boardHintTop * Theme.font.bodySmall / root.boardBodySmall)
    readonly property int hintBottom: Math.round(root.boardHintBottom * Theme.font.bodySmall / root.boardBodySmall)
    readonly property int hintLine: Math.round(Theme.font.caption * root.boardHintLineRatio)

    FontMetrics { id: bodyFace; font.family: Theme.font.family; font.pixelSize: Theme.font.body }
    FontMetrics { id: captionFace; font.family: Theme.font.family; font.pixelSize: Theme.font.caption }

    // A browser puts half of a line's leftover above its text, where a fixed Qt line puts all of it below, so the text box starts this far inside the band and the band's own bottom pad shrinks by it.
    readonly property int hintLead: Math.round((root.hintLine - Math.round(captionFace.ascent) - Math.round(captionFace.descent)) / 2)

    // A browser centres each line box on the row with its ascent and descent each rounded to whole pixels, so a baseline sits half of ascent less descent below the centre; the caption's baseline therefore sits this far from its label's, 1 px above at 14 over 12 (ClickAndRefresh F7).
    readonly property int captionShift: Math.round(((Math.round(captionFace.ascent) - Math.round(captionFace.descent))
                                                    - (Math.round(bodyFace.ascent) - Math.round(bodyFace.descent))) / 2)
}
