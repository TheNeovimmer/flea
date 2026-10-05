.import "../../ui/js/MarkdownPictures.js" as Pictures
.import "sourcefixture.js" as Source

// The inline pictures one Markdown text holds: which addresses load, and how a wide one is capped at the text it draws in.
function run(check) {
    function is(label, actual, expected) {
        check(label, JSON.stringify(actual), JSON.stringify(expected))
    }
    is("urls answers only the file URL beside a remote one in a code span",
        Pictures.urls("`![t](https://tracker.example/p.png)` and ![l](file:///d/p.png)"), ["file:///d/p.png"])
    is("urls answers nothing for a remote-only text",
        Pictures.urls("see ![t](https://tracker.example/p.png) here"), [])
    is("urls answers nothing for any other scheme",
        Pictures.urls("see ![t](data:image/png;base64,AAA) here"), [])
    is("urls answers both file URLs",
        Pictures.urls("a ![x](file:///d/p.png) b ![y](file:///d/q.png)"), ["file:///d/p.png", "file:///d/q.png"])
    is("an undecoded size leaves the text as is",
        Pictures.fit("a ![x](file:///p.png) b", {}, 100).text, "a ![x](file:///p.png) b")
    is("an undecoded size reports no tallest",
        Pictures.fit("a ![x](file:///p.png) b", {}, 100).tallest, 0)
    is("limit 0 leaves a wide picture as is",
        Pictures.fit("a ![x](file:///p.png) b", { "file:///p.png": { w: 160, h: 40 } }, 0).text, "a ![x](file:///p.png) b")
    is("a picture narrower than the limit stays",
        Pictures.fit("a ![x](file:///p.png) b", { "file:///p.png": { w: 60, h: 40 } }, 100).text, "a ![x](file:///p.png) b")
    is("a narrow picture reports its own height",
        Pictures.fit("a ![x](file:///p.png) b", { "file:///p.png": { w: 60, h: 40 } }, 100).tallest, 40)
    is("a wide picture is written scaled with its ratio kept",
        Pictures.fit("a ![x](file:///p.png) b", { "file:///p.png": { w: 160, h: 40 } }, 100).text,
        'a <img src="file:///p.png" width="100" height="25" /> b')
    is("a wide picture reports the scaled height",
        Pictures.fit("a ![x](file:///p.png) b", { "file:///p.png": { w: 160, h: 40 } }, 100).tallest, 25)
    is("a scaled height never falls to 0",
        Pictures.fit("a ![x](file:///p.png) b", { "file:///p.png": { w: 1000, h: 1 } }, 100).tallest, 1)
    is("a quote and an ampersand stay a well formed attribute",
        Pictures.fit('a ![x](file:///p/a"b&c.png) b', { 'file:///p/a"b&c.png': { w: 200, h: 50 } }, 100).text,
        'a <img src="file:///p/a%22b&amp;c.png" width="100" height="25" /> b')
    var gate = Source.slice(Source.source("ui/MarkdownText.qml"), "readonly property bool holdsPicture", "Component.onCompleted")
    var open = gate.indexOf("/", gate.indexOf("root.rich"))
    var close = gate.indexOf("/i.test(", open)
    is("holdsPicture is one file-scheme test", open >= 0 && close >= 0, true)
    // An ungated read proves nothing, so a missing gate never matches.
    var holds = open >= 0 && close >= 0 ? new RegExp(gate.substring(open + 1, close), "i") : /$^/
    is("a remote code span holds no picture", holds.test("`![t](https://tracker.example/p.png)`"), false)
    is("a file picture holds one", holds.test("see ![l](file:///d/p.png) here"), true)
    is("the helper builds only for a held picture", gate.indexOf("root.holdsPicture") >= 0, true)
}
