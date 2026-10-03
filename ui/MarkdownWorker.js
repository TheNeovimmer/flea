// MarkdownWorker.js: PreviewMarkdown's parser thread; WorkerScript binds no `.import` aliases, so Qt.include shares one scope with unique names.
Qt.include("js/Format.js");
Qt.include("js/MdUrl.js");
Qt.include("js/MdHtml.js");
Qt.include("js/MdEscape.js");
Qt.include("js/MdInline.js");
Qt.include("js/MdContainer.js");
Qt.include("js/MdRefs.js");
Qt.include("js/MdResolve.js");
Qt.include("js/MdRun.js");
Qt.include("js/MdLeaf.js");
Qt.include("js/MdDocument.js");
Qt.include("js/MdBlocks.js");

var Format = { date: date, fileUri: fileUri };
var MdUrl = { canonicalUrl: canonicalUrl, classifyImage: classifyImage, placeholder: placeholder };
var MdHtml = { closeToken: closeToken, openToken: openToken, documentText: documentText, normalizedTarget: normalizedTarget, readTag: readTag, sanitizeTag: sanitizeTag, tagHead: tagHead };
var MdEscape = { escapeText: escapeText, isAsciiPunct: isAsciiPunct };
var MdInline = { INTERVAL_STRIDE: INTERVAL_STRIDE, codeHtml: codeHtml, escapeHtmlText: escapeHtmlText, isPunct: isPunct, linkHtml: linkHtml, normalizeLabel: normalizeLabel, readAutolink: readAutolink, readBarelink: readBarelink, readInlineTarget: readInlineTarget, readLabelRef: readLabelRef, spanIntervals: spanIntervals };
var MdRefs = { readDefinition: readDefinition, readDefinitionTarget: readDefinitionTarget, readFootnoteDefinition: readFootnoteDefinition, killDefinition: killDefinition, readFootnoteRef: readFootnoteRef, skipDropContent: skipDropContent };
var MdResolve = { isLinkTarget: isLinkTarget, parseAngle: parseAngle, resolvePair: resolvePair, styledSpan: styledSpan };
var MdRun = { parseInline: parseInline };
var MdLeaf = { alertTitle: alertTitle, atxHeading: atxHeading, chunkList: chunkList, chunkTable: chunkTable, headingSafe: headingSafe, delimAligns: delimAligns, fenceOpen: fenceOpen, indentOf: indentOf, isThematic: isThematic, isSetext: isSetext, splitRow: splitRow, standaloneImage: standaloneImage, tableBlock: tableBlock, taskText: taskText };
var MdContainer = { readListMarker: readListMarker, indentationAt: indentationAt, takeIndent: takeIndent, quoteAt: quoteAt, takeQuote: takeQuote, listAt: listAt, takeList: takeList, textAt: textAt };
var MdDocument = { writer: writer, preparedText: preparedText };
var MdBlocks = { blocks: blocks, figureKind: figureKind };
// Short aliases the libraries use for each other, matching their `.import` names.
var Md = MdInline;
var Esc = MdEscape;
var Run = MdRun;
var Refs = MdRefs;
var Leaf = MdLeaf;
var Res = MdResolve;
var Container = MdContainer;
var Document = MdDocument;
var Html = MdHtml;

WorkerScript.onMessage = function (msg) {
    var blocks = [];
    var error = '';
    try {
        blocks = MdBlocks.blocks(msg.source, msg.dir, msg.chrome, msg.ink);
    } catch (e) {
        error = String(e);
    }
    WorkerScript.sendMessage({ seq: msg.seq, blocks: blocks, error: error });
};
