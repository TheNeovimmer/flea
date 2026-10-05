.import "../../ui/js/Markdown.js" as Markdown

// A document's line endings are LF, CR or CRLF: the same text in any of them draws the same blocks, and no fence line stays text.
function run(check) {
    var dir = "/home/gm/notes"
    var shapes = {
        "a fence": "a\n\n```toml\nk = 1\n```\n\nb\n",
        "a fence without a language": "a\n\n```\ncode\n```\n",
        "a tilde fence": "a\n\n~~~\ncode\n~~~\n",
        "a fence after a heading": "## h\n````ts\nx\n````\n",
        "a fence after a table": "| a | b |\n|---|---|\n| 1 | 2 |\n```\ncode\n```\n",
        "a fence in a list item": "- item\n\n  ```\n  code\n  ```\n- two\n",
        "an unclosed fence": "text\n\n```\ncode\nmore\n"
    }
    function kinds(doc) {
        return Markdown.blocks(doc, dir).map(function (b) { return b.type }).join(",")
    }
    for (var name in shapes) {
        var lf = kinds(shapes[name])
        check(name + " opens as a code block", lf.indexOf("fence") >= 0 || lf.indexOf("list") >= 0, true)
        check(name + " draws the same in CRLF", kinds(shapes[name].replace(/\n/g, "\r\n")), lf)
        check(name + " draws the same in CR", kinds(shapes[name].replace(/\n/g, "\r")), lf)
    }
    check("a CRLF fence carries its text without the carriage returns", Markdown.blocks("```js\r\nvar a = 1;\r\n```\r\n", dir)[0].text, "var a = 1;")
    check("a CRLF heading carries no carriage return", Markdown.blocks("# Hi\r\n", dir)[0].text, "Hi")
}
