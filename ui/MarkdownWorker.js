// MarkdownWorker.js: PreviewMarkdown's parser thread; WorkerScript binds no `.import` aliases, so Qt.include shares one scope with unique names.
Qt.include("js/Format.js");
Qt.include("js/MdUrl.js");
Qt.include("js/MdHtml.js");
Qt.include("js/MdEscape.js");
Qt.include("js/MdInline.js");
Qt.include("js/MdRefs.js");
Qt.include("js/MdResolve.js");
Qt.include("js/MdRun.js");
Qt.include("js/MdLeaf.js");
Qt.include("js/MdBlocks.js");

var Format = { date: date, fileUri: fileUri };
var MdUrl = { canonicalUrl: canonicalUrl, classifyImage: classifyImage, placeholder: placeholder };
var MdHtml = { closeToken: closeToken, openToken: openToken, readTag: readTag, sanitizeTag: sanitizeTag, tagHead: tagHead };
var MdEscape = { escapeText: escapeText, isAsciiPunct: isAsciiPunct };
var MdInline = { codeHtml: codeHtml, escapeHtmlText: escapeHtmlText, isPunct: isPunct, linkHtml: linkHtml, normalizeLabel: normalizeLabel, readAutolink: readAutolink, readBarelink: readBarelink, readInlineTarget: readInlineTarget, readLabelRef: readLabelRef, spanIntervals: spanIntervals };
var MdRefs = { collectDefs: collectDefs, collectFootnotes: collectFootnotes, killDefinition: killDefinition, readFootnoteRef: readFootnoteRef, skipDropContent: skipDropContent };
var MdResolve = { isLinkTarget: isLinkTarget, parseAngle: parseAngle, resolvePair: resolvePair, styledSpan: styledSpan };
var MdRun = { parseInline: parseInline };
var MdLeaf = { alertTitle: alertTitle, atxHeading: atxHeading, delimAligns: delimAligns, fenceOpen: fenceOpen, headingSafe: headingSafe, indentOf: indentOf, isThematic: isThematic, prepare: prepare, splitRow: splitRow, standaloneImage: standaloneImage, tableBlock: tableBlock, taskText: taskText };
var MdBlocks = { blocks: blocks, figureKind: figureKind };
// Short aliases the libraries use for each other, matching their `.import` names.
var Md = MdInline;
var Esc = MdEscape;
var Run = MdRun;
var Refs = MdRefs;
var Leaf = MdLeaf;
var Res = MdResolve;

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
