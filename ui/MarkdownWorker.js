// MarkdownWorker.js: PreviewMarkdown's parser thread. WorkerScript does not
// bind `.import ... as ...` aliases (verified on this Qt), so the libraries load
// through Qt.include and the namespaces below rebind the globals each file
// declares. The set holds zero top-level collisions, so the shared scope is
// safe; a missing entry fails loud as a ReferenceError in the worker reply.
Qt.include("js/Format.js");
Qt.include("js/MdUrl.js");
Qt.include("js/MdHtml.js");
Qt.include("js/MdInline.js");
Qt.include("js/MdRefs.js");
Qt.include("js/MdResolve.js");
Qt.include("js/MdRun.js");
Qt.include("js/MdLeaf.js");
Qt.include("js/MdBlocks.js");

var Format = { date: date, fileUri: fileUri };
var MdUrl = { canonicalUrl: canonicalUrl, classifyImage: classifyImage, placeholder: placeholder };
var MdHtml = { closeToken: closeToken, openToken: openToken, readTag: readTag, sanitizeTag: sanitizeTag, tagHead: tagHead };
var MdInline = { codeHtml: codeHtml, escapeHtmlText: escapeHtmlText, isPunct: isPunct, linkHtml: linkHtml, normalizeLabel: normalizeLabel, readAutolink: readAutolink, readBarelink: readBarelink, readInlineTarget: readInlineTarget, readLabelRef: readLabelRef, spanIntervals: spanIntervals };
var MdRefs = { collectDefs: collectDefs, collectFootnotes: collectFootnotes, killDefinition: killDefinition, readFootnoteRef: readFootnoteRef, skipDropContent: skipDropContent };
var MdResolve = { isLinkTarget: isLinkTarget, parseAngle: parseAngle, resolvePair: resolvePair, styledSpan: styledSpan };
var MdRun = { parseInline: parseInline };
var MdLeaf = { alertTitle: alertTitle, delimAligns: delimAligns, fenceOpen: fenceOpen, indentOf: indentOf, isThematic: isThematic, prepare: prepare, splitRow: splitRow, standaloneImage: standaloneImage, tableBlock: tableBlock, taskText: taskText };
var MdBlocks = { blocks: blocks, figureKind: figureKind };
// Short aliases the libraries use for each other, matching their `.import` names.
var Md = MdInline;
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
