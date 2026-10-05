.pragma library

// The spec harness's normaliser: HTML to the structure a reader sees, inline markup flattened to runs, so two serialisations compare equal.

var BLOCK_TAGS = { blockquote: 1, ul: 1, ol: 1, li: 1, p: 1, h1: 1, h2: 1, h3: 1, h4: 1, h5: 1, h6: 1,
    pre: 1, hr: 1, table: 1, thead: 1, tbody: 1, tr: 1, th: 1, td: 1 }
var VOID_TAGS = { br: 1, hr: 1, img: 1, input: 1, source: 1 }
// Tags Flea's sanitiser drops with their content (MdHtml DROP_CONTENT).
var DROP_CONTENT = { script: 1, style: 1, iframe: 1, object: 1, embed: 1, template: 1, noscript: 1, svg: 1, math: 1 }
var ENTITIES = { amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", nbsp: " " }
var INLINE_FORMAT = { strong: "b", b: "b", em: "i", i: "i", code: "code", kbd: "code", del: "s", s: "s",
    strike: "s", sup: "sup", sub: "sub" }

// Sample input: "&amp; &#35; &#x23;" decodes to "& # #"; an unknown name stays as written.
function decode(text) {
    return text.replace(/&(?:#(\d+)|#[xX]([0-9a-fA-F]+)|([A-Za-z][A-Za-z0-9]*));/g, function (all, dec, hex, name) {
        if (dec !== undefined || hex !== undefined) {
            var code = dec !== undefined ? parseInt(dec, 10) : parseInt(hex, 16)
            return code > 0 && code <= 0x10ffff ? String.fromCodePoint(code) : all
        }
        return ENTITIES.hasOwnProperty(name) ? ENTITIES[name] : all
    })
}

// Sample input: '<a href="x" b>' answers { name: "a", attrs: { href: "x", b: "" } }.
function readAttrs(rest) {
    var attrs = {}
    var re = /([^\s"'<>\/=]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g
    var m
    while ((m = re.exec(rest)) !== null)
        attrs[m[1].toLowerCase()] = decode(m[2] !== undefined ? m[2] : m[3] !== undefined ? m[3] : m[4] !== undefined ? m[4] : "")
    return attrs
}

// Sample input: "<ul><li>a</li></ul>" answers { tag: "", kids: [{ tag: "ul", kids: [{ tag: "li", kids: [{ text: "a" }] }] }] }.
function parse(html) {
    var root = { tag: "", attrs: {}, kids: [] }
    var stack = [root]
    var re = /<!--[\s\S]*?-->|<\?[\s\S]*?\?>|<![A-Za-z][^>]*>|<!\[CDATA\[[\s\S]*?\]\]>|<(\/?)([A-Za-z][A-Za-z0-9-]*)((?:"[^"]*"|'[^']*'|[^>"'])*)>/g
    var at = 0
    var m
    function text(raw) {
        if (raw.length > 0)
            stack[stack.length - 1].kids.push({ text: decode(raw) })
    }
    while ((m = re.exec(html)) !== null) {
        text(html.slice(at, m.index))
        at = re.lastIndex
        if (m[2] === undefined)
            continue
        var name = m[2].toLowerCase()
        if (m[1] === "/") {
            for (var s = stack.length - 1; s > 0; s--) {
                if (stack[s].tag === name) {
                    stack.length = s
                    break
                }
            }
            continue
        }
        var node = { tag: name, attrs: readAttrs(m[3].replace(/\/\s*$/, "")), kids: [] }
        stack[stack.length - 1].kids.push(node)
        if (!VOID_TAGS.hasOwnProperty(name) && !/\/\s*$/.test(m[3]))
            stack.push(node)
    }
    text(html.slice(at))
    return root
}

// Sample input: "%20" and "%C3%A9" decode so "a%20b" and "a b" read as one link target.
function target(url) {
    var safe = String(url).replace(/%(?![0-9A-Fa-f]{2})/g, "%25")
    try {
        return decodeURIComponent(safe)
    } catch (e) {
        return String(url)
    }
}

// Flatten inline nodes to runs: { t, k } text with a format key, or { atom } for a break, image or checkbox.
function runsOf(nodes, fmt, link, out, design) {
    for (var i = 0; i < nodes.length; i++) {
        var n = nodes[i]
        if (n.text !== undefined) {
            out.push({ t: n.text, k: fmt.join(",") + (link !== null ? "|a=" + link : "") })
            continue
        }
        if (design && DROP_CONTENT.hasOwnProperty(n.tag))
            continue
        if (n.tag === "br") {
            out.push({ atom: "br" })
        } else if (n.tag === "img") {
            out.push({ atom: "img src=" + target(n.attrs.src || "") + " alt=" + (n.attrs.alt || "") })
        } else if (n.tag === "input") {
            out.push({ atom: "checkbox" + (n.attrs.checked !== undefined ? " checked" : "") })
        } else if (n.tag === "a") {
            runsOf(n.kids, fmt, n.attrs.href !== undefined ? target(n.attrs.href) : link, out, design)
        } else if (INLINE_FORMAT.hasOwnProperty(n.tag)) {
            var key = INLINE_FORMAT[n.tag]
            runsOf(n.kids, fmt.indexOf(key) >= 0 ? fmt : fmt.concat([key]).sort(), link, out, design)
        } else {
            runsOf(n.kids, fmt, link, out, design)
        }
    }
}

// Sample input: runs "a ", "b" in bold, " c" read "a ⟦b|b⟧ c"; spaces collapse across runs and trim at both ends.
function runsText(runs) {
    var parts = []
    var pendingSpace = false
    var started = false
    function push(piece) {
        parts.push(piece)
        started = true
    }
    var merged = []
    for (var i = 0; i < runs.length; i++) {
        var last = merged.length > 0 ? merged[merged.length - 1] : null
        if (runs[i].atom === undefined && last !== null && last.atom === undefined && last.k === runs[i].k)
            last.t += runs[i].t
        else
            merged.push(runs[i].atom === undefined ? { t: runs[i].t, k: runs[i].k } : runs[i])
    }
    for (var m = 0; m < merged.length; m++) {
        var r = merged[m]
        if (r.atom !== undefined) {
            if (r.atom === "br")
                pendingSpace = false
            if (pendingSpace && started && r.atom !== "br")
                push(" ")
            pendingSpace = false
            push("⟦" + r.atom + "⟧")
            if (r.atom === "br")
                started = false
            continue
        }
        var words = r.t.replace(/[ \t\r\n\f]+/g, " ")
        if (words === "")
            continue
        var lead = words.charAt(0) === " "
        var trail = words.charAt(words.length - 1) === " "
        var core = words.replace(/^ | $/g, "")
        if (core === "") {
            pendingSpace = pendingSpace || started
            continue
        }
        if ((lead || pendingSpace) && started)
            push(" ")
        push(r.k === "" ? core : "⟦" + r.k + "|" + core + "⟧")
        pendingSpace = trail
    }
    return parts.join("")
}

function isBlock(n) {
    return n.tag !== undefined && (BLOCK_TAGS.hasOwnProperty(n.tag) || n.tag === "div" || n.tag === "details" || n.tag === "summary" || n.tag === "picture")
}

function blank(runs) {
    return runsText(runs) === ""
}

// A flow of children: block elements serialise themselves; a run of inline children becomes one paragraph, or loose text inside an item or cell.
function flow(nodes, loose, design) {
    var out = []
    var inline = []
    function flush() {
        if (inline.length === 0)
            return
        var runs = []
        runsOf(inline, [], null, runs, design)
        inline = []
        if (!blank(runs))
            out.push(loose ? "<t>" + runsText(runs) + "</t>" : "<p>" + runsText(runs) + "</p>")
    }
    for (var i = 0; i < nodes.length; i++) {
        var n = nodes[i]
        if (design && n.tag !== undefined && DROP_CONTENT.hasOwnProperty(n.tag))
            continue
        if (!isBlock(n)) {
            inline.push(n)
            continue
        }
        flush()
        out.push(blockOf(n, design))
    }
    flush()
    return out.join("")
}

function blockOf(n, design) {
    var t = n.tag
    if (t === "hr")
        return "<hr>"
    if (t === "pre") {
        var code = n.kids.length === 1 && n.kids[0].tag === "code" ? n.kids[0] : n
        var raw = ""
        for (var i = 0; i < code.kids.length; i++)
            raw += code.kids[i].text !== undefined ? code.kids[i].text : ""
        var cls = /(?:^|\s)language-(\S+)/.exec(code.attrs["class"] || "")
        return "<pre" + (cls !== null ? " lang=" + cls[1] : "") + ">" + raw.replace(/ /g, "␠").replace(/\n/g, "␤") + "</pre>"
    }
    if (t === "p" || /^h[1-6]$/.test(t)) {
        var runs = []
        runsOf(n.kids, [], null, runs, design)
        // An empty paragraph draws nothing.
        return t === "p" && blank(runs) ? "" : "<" + t + ">" + runsText(runs) + "</" + t + ">"
    }
    if (t === "div" || t === "details" || t === "summary" || t === "picture")
        return flow(n.kids, false, design)
    var attrs = ""
    if (t === "ol" && n.attrs.start !== undefined && n.attrs.start !== "1")
        attrs = " start=" + n.attrs.start
    if ((t === "th" || t === "td") && n.attrs.align !== undefined && n.attrs.align !== "left")
        attrs = " align=" + n.attrs.align
    var loose = t === "li" || t === "th" || t === "td"
    return "<" + t + attrs + ">" + flow(n.kids, loose, design) + "</" + t + ">"
}

// Sample input: "<p>a  <em>b</em></p>" answers "<p>a ⟦i|b⟧</p>"; design maps what Flea never draws out of the expected side.
function canon(html, design) {
    return flow(parse(html).kids, false, design === true)
}
