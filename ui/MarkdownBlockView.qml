import QtQuick
import "." as Flea
import "js/Markdown.js" as Markdown
import "js/MdHtmlImage.js" as HtmlImage

// One Markdown block, built as the one kind it is, at the top of the document or inside an item or a quote.
Item {
    id: view

    property var block: ({})
    property int blockIndex: -1
    // How many blocks the list holding this one has, so the last one knows nothing follows it.
    property int blockCount: 0
    // The preview that sets the document's sizes and colours.
    property Item preview: null
    // Only a figure intersecting the viewport may send a render request.
    property bool inView: true

    // A picture followed by another block keeps the pane's block gap under it too, as a paragraph does, so what follows never touches it.
    readonly property int pictureGap: (view.block.type === "images" || view.block.type === "image") && view.blockIndex < view.blockCount - 1 ? view.preview.blockGap : 0
    // Only the drawn block lends its height, and a list or table chunk lies flush by its own negative y.
    height: kind.item ? kind.item.height + kind.item.y + view.pictureGap : 0

    // A block builds only the parts its own kind draws, on the view; an empty heading or quote builds none, so it has no height.
    Loader {
        id: kind
        sourceComponent: view.block.text === "" && view.block.parts === undefined && (view.block.type === "heading" || view.block.type === "quote") ? null : view.block.type === "run" && view.block.maths !== undefined ? mathsBlock
            : view.block.type === "run" || view.block.type === "heading" ? textBlock
            : view.block.type === "fence" ? fenceBlock
            : view.block.type === "figure" ? figureBlock
            : view.block.type === "quote" ? quoteBlock
            : view.block.type === "remote" ? remoteBlock
            : view.block.type === "list" ? listBlock
            : view.block.type === "table" ? tableBlock
            : view.block.type === "images" ? imagesBlock : imageBlock
        onLoaded: kind.item.parent = view
    }

    // Headings use the prescribed bold text size and line box.
    Component {
        id: textBlock
        Flea.MarkdownText {
            linkGate: Markdown.isExternalLink
            width: view.width
            bodyPx: view.preview.bodyPx
            markdown: view.block.text
            font.pixelSize: view.block.type === "heading" ? view.preview.headingPx(view.block.level) : view.preview.bodyPx
            font.bold: view.block.type === "heading"
            // h1 and h2 take the bright foreground; deeper levels and body stay the foreground.
            color: view.block.type === "heading" && view.block.level <= view.preview.boardHeadings.length ? Theme.color.foregroundBright : Theme.color.foreground
        }
    }

    // A run with inline formulas draws each in its line once the helper answers; the other runs build none of its parts.
    Component {
        id: mathsBlock
        Flea.MarkdownMathsText {
            objectName: "mathsText"
            linkGate: Markdown.isExternalLink
            width: view.width
            bodyPx: view.preview.bodyPx
            source: view.block.text
            maths: view.block.maths
            askArmed: view.preview.figuresArmed
            inView: view.inView
            bgHex: view.preview.hexOf(Theme.color.background)
            fgHex: view.preview.inkHex
            accentHex: view.preview.accentHex
            mutedHex: view.preview.mutedHex
            surfaceHex: view.preview.surfaceHex
            font.pixelSize: view.preview.bodyPx
        }
    }

    Component {
        id: tableBlock
        Flea.MarkdownTable {
            block: view.block
            preview: view.preview
            availableWidth: view.width
        }
    }

    // A fenced block is a filled block on the code surface with no border.
    Component {
        id: fenceBlock
        Rectangle {
            id: fenceBox
            objectName: "fenceBox"
            width: view.width
            height: fenceText.implicitHeight + 2 * view.preview.fencePadY
            color: view.preview.codeSurface

            Text {
                id: fenceText
                anchors.fill: parent
                anchors.leftMargin: view.preview.fencePadX
                anchors.rightMargin: view.preview.fencePadX
                anchors.topMargin: view.preview.fencePadY
                anchors.bottomMargin: view.preview.fencePadY
                text: view.block.text
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: Theme.color.foreground
                font.family: Theme.font.family
                font.pixelSize: view.preview.bodyPx
            }
        }
    }

    // Display maths use the figure fallback's vertical inset; the list owns the block gap.
    Component {
        id: figureBlock
        Item {
            id: figureBox
            objectName: "figureBox"
            width: view.width
            readonly property int figureInset: figureItem.ready && figureItem.kind === "math" && figureItem.fitHeight > 0 ? Theme.spacing.gap : 0
            height: figureItem.implicitHeight + 2 * figureInset

            Flea.MarkdownFigure {
                id: figureItem
                objectName: "figureItem"
                y: parent.figureInset
                width: parent.width
                kind: view.block.kind
                source: view.block.source
                display: true
                askArmed: view.preview.figuresArmed
                inView: view.inView
                bgHex: view.preview.hexOf(Theme.color.background)
                fgHex: view.preview.inkHex
                accentHex: view.preview.accentHex
                mutedHex: view.preview.mutedHex
                surfaceHex: view.preview.surfaceHex
                fallbackColor: view.preview.codeSurface
                fontFamily: Theme.font.family
                bodyPx: view.preview.bodyPx
            }
        }
    }

    // A quote draws one bar per level, and a joined block sits flush under the one above so the outer bars run on.
    Component {
        id: quoteBlock
        Flea.MarkdownQuote {
            objectName: "quoteRow"
            y: view.block.joined === true ? -view.preview.blockGap : 0
            width: view.width
            levels: view.block.depth !== undefined ? view.block.depth : 1
            linkGate: Markdown.isExternalLink
            bodyPx: view.preview.bodyPx
            text: view.block.text
            parts: view.block.parts !== undefined ? view.block.parts : []
            preview: view.preview
            inView: view.inView
        }
    }

    // A chunk after the first sits flush under its predecessor, across the gap the list puts between blocks.
    Component {
        id: listBlock
        Flea.MarkdownList {
            objectName: "listColumn"
            y: view.block.joined === true ? -view.preview.blockGap : 0
            width: view.width
            list: view.block
            gap: view.preview.blockGap
            linkGate: Markdown.isExternalLink
            bodyPx: view.preview.bodyPx
            preview: view.preview
            inView: view.inView
        }
    }

    Component {
        id: remoteBlock
        Flea.MarkdownRemote {
            width: view.width
            host: view.block.host
        }
    }

    // A badge row builds only its own pictures, wrapped and aligned by the row itself.
    Component {
        id: imagesBlock
        Flea.MarkdownImages {
            width: view.width
            images: view.block.type === "images" ? view.block.items : []
            centred: view.block.type === "images" && view.block.align === "center"
            gap: view.preview.blockGap
            linkGate: Markdown.isExternalLink
        }
    }

    Component {
        id: imageBlock
        Image {
            id: localImage
            // The size rule of the badge row (HtmlImage.pictureSize); its paragraph's align="center" centres it.
            readonly property var fit: HtmlImage.pictureSize(view.block.type === "image" ? view.block : ({}), localImage.implicitWidth, localImage.implicitHeight, view.width)
            width: localImage.fit.w
            height: localImage.fit.h
            x: view.block.type === "image" && view.block.align === "center" ? Math.round((view.width - localImage.width) / 2) : 0
            fillMode: localImage.fit.stretch ? Image.Stretch : Image.PreserveAspectFit
            visible: view.block.type === "image"
            asynchronous: true
            autoTransform: true
            source: view.block.type === "image" ? view.block.url : ""

            // A logo wrapped in a link opens it through the pane's link gate.
            TapHandler { enabled: view.block.link !== undefined; gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: if (Markdown.isExternalLink(view.block.link)) Qt.openUrlExternally(view.block.link) }
            HoverHandler { enabled: view.block.link !== undefined; cursorShape: Qt.PointingHandCursor }
        }
    }
}
