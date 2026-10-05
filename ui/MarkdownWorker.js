// MarkdownWorker.js: PreviewMarkdown's parser thread; WorkerScript binds no `.import` aliases, so Qt.include shares one scope with unique names.
Qt.include("js/Format.js");
Qt.include("js/MdUrl.js");
Qt.include("js/MdHtml.js");
Qt.include("js/MdHtmlImage.js");
Qt.include("js/MdHtmlBlock.js");
Qt.include("js/MdEscape.js");
Qt.include("js/MdInline.js");
Qt.include("js/MdLink.js");
Qt.include("js/MdContainer.js");
Qt.include("js/MdRefs.js");
Qt.include("js/MdEntityTable.js");
Qt.include("js/MdEntity.js");
Qt.include("js/MdResolve.js");
Qt.include("js/MdEmph.js");
Qt.include("js/MdBreak.js");
Qt.include("js/MdHold.js");
Qt.include("js/MdRun.js");
Qt.include("js/MdLeaf.js");
Qt.include("js/MdItems.js");
Qt.include("js/MdChunks.js");
Qt.include("js/MdDocument.js");
Qt.include("js/MdMath.js");
Qt.include("js/MdFront.js");
Qt.include("js/MdBlocks.js");

var Format = { date: date, fileUri: fileUri };
var MdUrl = { canonicalUrl: canonicalUrl, classifyImage: classifyImage, placeholder: placeholder, srcsetPick: srcsetPick, strippedTarget: strippedTarget, targetAllowed: targetAllowed };
var MdHtml = { closeToken: closeToken, openToken: openToken, documentText: documentText, normalizedTarget: normalizedTarget, readTag: readTag, sanitizeTag: sanitizeTag, tagHead: tagHead };
var MdHtmlImage = { imageUnit: imageUnit, rawImage: rawImage, isCentred: isCentred, linkOf: linkOf, LEADING_BREAK: LEADING_BREAK };
var MdHtmlBlock = { splitHtmlImages: splitHtmlImages, separateBlocks: separateBlocks };
var MdEscape = { escapeText: escapeText, isAsciiPunct: isAsciiPunct };
var MdInline = { INTERVAL_STRIDE: INTERVAL_STRIDE, MATH_SPAN: MATH_SPAN, isSpace: isSpace, codeHtml: codeHtml, escapeDecodedText: escapeDecodedText, escapeHtmlText: escapeHtmlText, isPunct: isPunct, linkHtml: linkHtml, spanIntervals: spanIntervals };
var MdLink = { angleClose: angleClose, normalizeLabel: normalizeLabel, readAutolink: readAutolink, readBarelink: readBarelink, readInlineTarget: readInlineTarget, readLabelRef: readLabelRef };
var MdRefs = { readDefinition: readDefinition, hideTitle: hideTitle, storeDefinition: storeDefinition, readDefinitionParts: readDefinitionParts, readDefinitionTarget: readDefinitionTarget, titleEnd: titleEnd, readFootnoteDefinition: readFootnoteDefinition, killDefinition: killDefinition, readFootnoteRef: readFootnoteRef, skipDropContent: skipDropContent, definitionAt: definitionAt, hideDefinition: hideDefinition };
var MdEntityTable = { namedValue: namedValue };
var MdEntity = { lineBlank: lineBlank, lineRestart: lineRestart, lineState: lineState, drawnText: drawnText, spaceRunAt: spaceRunAt, codePointText: codePointText, decodeReferences: decodeReferences, referenceAt: referenceAt };
var MdEmph = { literal: literal, process: process, runAt: runAt };
var MdBreak = { isRuleLine: isRuleLine, lineBreak: lineBreak, quoteMarkAt: quoteMarkAt };
var MdResolve = { bareAt: bareAt, isLinkTarget: isLinkTarget, parseAngle: parseAngle, plainText: plainText, readDestination: readDestination, readRawDestination: readRawDestination, resolvePair: resolvePair, styledSpan: styledSpan };
var MdHold = { hold: hold };
var MdRun = { parseInline: parseInline };
var MdLeaf = { alertTitle: alertTitle, atxHeading: atxHeading, chunkTable: chunkTable, LIST_CHUNK_ITEMS: LIST_CHUNK_ITEMS, headingSafe: headingSafe, delimAligns: delimAligns, fenceOpen: fenceOpen, indentOf: indentOf, isThematic: isThematic, isSetext: isSetext, setextLevel: setextLevel, splitRow: splitRow, standaloneImage: standaloneImage, tableBlock: tableBlock, taskText: taskText, pinTaskBox: pinTaskBox };
var MdContainer = { readListMarker: readListMarker, indentationAt: indentationAt, takeIndent: takeIndent, quoteAt: quoteAt, takeQuote: takeQuote, listAt: listAt, takeList: takeList, startsBlock: startsBlock, textAt: textAt, unindent: unindent, expandLead: expandLead };
var MdItems = { builder: builder, content: content, inlineLines: inlineLines, isRaw: isRaw, listBlock: listBlock, quoteBlocks: quoteBlocks, visibleLines: visibleLines };
var MdChunks = { chunkList: chunkList };
var MdMath = { displayAt: displayAt, inlineSources: inlineSources, splitDisplay: splitDisplay };
var MdFront = { closeAt: closeAt, sendFront: sendFront };
var MdDocument = { writer: writer, preparedText: preparedText };
var MdBlocks = { blocks: blocks, figureKind: figureKind };
// Short aliases the libraries use for each other, matching their `.import` names.
var Names = MdEntityTable;
var Md = MdInline;
var Link = MdLink;
var Esc = MdEscape;
var Run = MdRun;
var Hold = MdHold;
var Emph = MdEmph;
var Ent = MdEntity;
var Brk = MdBreak;
var Refs = MdRefs;
var Leaf = MdLeaf;
var Res = MdResolve;
var Container = MdContainer;
var Document = MdDocument;
var Front = MdFront;
var Items = MdItems;
var Chunks = MdChunks;
var Maths = MdMath;
var Html = MdHtml;
var HtmlImage = MdHtmlImage;
var HtmlBlock = MdHtmlBlock;

WorkerScript.onMessage = function (msg) {
    var blocks = [];
    var error = '';
    try {
        // A first parse of a file sends its head ahead, so the first screen draws while the rest is still parsing.
        blocks = MdBlocks.blocks(msg.source, msg.dir, msg.chrome, msg.ink, msg.head, function (head) {
            WorkerScript.sendMessage({ seq: msg.seq, blocks: head, error: '', partial: true });
        });
    } catch (e) {
        error = String(e);
    }
    WorkerScript.sendMessage({ seq: msg.seq, blocks: blocks, error: error });
};
