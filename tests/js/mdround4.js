.import "../../ui/js/Markdown.js" as Markdown
.import "../../ui/js/MdBlocks.js" as MdBlocks
.import "../../ui/js/MdHtml.js" as MdHtml
.import "../../ui/js/MdUrl.js" as MdUrl
.import "sourcefixture.js" as Source

// Closing round 4 of the Markdown parser: bounded display math, hostile keys, one block pass, named limits, backslash dirs.
function run(check) {
    var dir = "/doc"
    var chrome = "#181825"
    var ink = "#c0caf5"
    function blocks(doc, where) { return Markdown.blocks(doc, where === undefined ? dir : where, chrome, ink) }
    function types(doc) { return blocks(doc).map(function (b) { return b.type }).join(",") }
    function figures(doc) { return blocks(doc).filter(function (b) { return b.type === "figure" }) }

    check("md3u r4 F1 two-line block is one figure", JSON.stringify(blocks("$$\nx^2\n$$")),
        JSON.stringify([{ type: "figure", kind: "math", source: "x^2", display: true }]))
    check("md3u r4 F1 three-line block is one figure", figures("$$\na\nb\n$$")[0].source, "a\nb")
    var stray = "$$ open\n\nprose line\n\n$$ later"
    check("md3u r4 F1 opener, blank, prose, later $$ emits no figure", figures(stray).length, 0)
    var strayText = blocks(stray).map(function (b) { return b.text }).join("\n")
    check("md3u r4 F1 every line stays text", strayText.indexOf("open") >= 0 && strayText.indexOf("prose line") >= 0
        && strayText.indexOf("later") >= 0, true)
    var fenced = "$$ open\n\n```\ncode\n```\n\n$$ later"
    check("md3u r4 F1 a fence after an unclosed opener stays a fence", types(fenced).indexOf("fence") >= 0
        && figures(fenced).length === 0, true)
    check("md3u r4 F1 blank line with spaces also ends the search", figures("$$ open\n   \nprose\n$$ later").length, 0)
    check("md3u r4 F1 closer after prose in one paragraph still closes", figures("$$\nx\ny $$ tail")[0].source, "x\ny")
    check("md3u r4 F1 two blocks apart emit two figures", figures("$$\na\n$$\n\n$$\nb\n$$").length, 2)

    var hostile = ["hasOwnProperty", "constructor", "__proto__", "toString", "valueOf"]
    function noteDoc(id) { return "x[^" + id + "] y[^other]\n\n[^" + id + "]: note\n[^other]: more" }
    for (var n = 0; n < hostile.length; n++) {
        var hostileNote = "threw"
        try {
            hostileNote = JSON.stringify(blocks(noteDoc(hostile[n])))
        } catch (noteError) {
            hostileNote = "threw " + noteError.message
        }
        check("md3u r4 F2 footnote id " + hostile[n] + " numbers like a plain one", hostileNote, JSON.stringify(blocks(noteDoc("aa"))))
    }
    var defDoc = function (id) { return "![x][" + id + "]\n\n[" + id + "]: pic.png" }
    for (var h = 0; h < hostile.length; h++) {
        var hostileDef = "threw"
        try {
            hostileDef = JSON.stringify(blocks(defDoc(hostile[h])))
        } catch (err) {
            hostileDef = "threw " + err.message
        }
        check("md3u r4 F2 reference id " + hostile[h], hostileDef, JSON.stringify(blocks(defDoc("aa"))))
    }
    var protoDef = "threw"
    try {
        protoDef = Markdown.definitions("[__proto__]: pic.png")["__proto__"]
    } catch (protoError) {
        protoDef = "threw " + protoError.message
    }
    check("md3u r4 F2 definitions answer a __proto__ id", protoDef, "pic.png")

    // One block pass collects everything prepare() needs, so a second pass over the same lines adds nothing.
    var passDocs = ["[a]: pic.png\n\n![x][a]", "[a]:\n  pic.png\n\ntext", "[^1]: n\n    more\n\nsee[^1]", "```\n[a]: b\n```\n\n[c]: d",
        "---\ntitle: x\n---\n\n$$\nx\n$$", "> [b]: x.png\n\n- [c]: y.png\n\n    code"]
    for (var p = 0; p < passDocs.length; p++) {
        var passLines = MdHtml.documentText(passDocs[p]).split("\n")
        var passState = MdBlocks.referenceState()
        MdBlocks.blockPass(passLines, passState, undefined, true)
        var collected = JSON.stringify(passState)
        MdBlocks.blockPass(passLines, passState, undefined, false)
        check("md3u r4 F3 second pass leaves the state alone " + p, JSON.stringify(passState), collected)
    }
    check("md3u r4 F3 prepare runs one block pass",
        /blockPass\(lines, state, undefined, false\)\n\s+return Document\.preparedText/.test(Source.source("ui/js/MdBlocks.js")), false)

    var leafSource = Source.source("ui/js/MdLeaf.js")
    var atx = Source.slice(leafSource, "function atxHeading(", "function headingSafe(")
    check("md3u r4 F4 atxHeading names its indent and level limits", /i < 3\b|level > 6/.test(atx), false)
    check("md3u r4 F4 headingSafe names its digit limit", /\{1,9\}|#\{1,6\}/.test(Source.slice(leafSource, "function headingSafe(", "return block")), false)
    check("md3u r4 F4 MdLeaf declares the shared names",
        /var MAX_MARKER_INDENT = 3\b/.test(leafSource) && /var MAX_MARKER_DIGITS = 9\b/.test(leafSource)
        && /var MAX_HEADING_LEVEL = 6\b/.test(leafSource), true)

    var spaced = "/docs/a\\b"
    function classified(raw, where) { return MdUrl.classifyImage(raw, where === undefined ? spaced : where) }
    check("md3u r4 F6 image in a backslash folder stays local", classified("pic.png").kind, "local")
    check("md3u r4 F6 its url carries the folder's backslash encoded", String(classified("pic.png").url), "file:///docs/a%5Cb/pic.png")
    check("md3u r4 F6 dot-slash form", classified("./sub/pic.png").kind, "local")
    check("md3u r4 F6 a backslash in the reference is refused", classified("a\\b.png", "/docs").kind, "dropped")
    check("md3u r4 F6 an absolute reference with a backslash is refused", classified("/docs/a\\b/pic.png").kind, "dropped")
    check("md3u r4 F6 a file url with a backslash is refused", classified("file:///docs/a\\b/pic.png").kind, "dropped")
    check("md3u r4 F6 leaving the folder stays refused", classified("../pic.png").kind, "dropped")
    check("md3u r4 F6 climbing past the folder stays refused", classified("sub/../../pic.png").kind, "dropped")
    check("md3u r4 F6 a sibling absolute path stays refused", classified("/docs/other/pic.png").kind, "dropped")
    check("md3u r4 F6 a file url outside stays refused", classified("file:///docs/pic.png").kind, "dropped")
    check("md3u r4 F6 a plain folder still resolves", classified("pic.png", "/docs/a").kind, "local")
}
