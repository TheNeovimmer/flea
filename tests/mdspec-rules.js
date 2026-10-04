.pragma library

// The deliberate differences from the spec, each with the rule that causes it. An example named here that the parser now draws
// right fails the run as stale, so a rule never outlives its cause.
var RULES = {
    "front-matter": {
        text: "A first line of three dashes opens YAML front matter, which draws as a code block (MdBlocks), so a leading thematic break is not one.",
        ids: ["96", "98"]
    },
    "empty-block": {
        text: "A heading or a quote with nothing to draw draws nothing: an empty heading, an empty quote, a quote holding only definitions or an empty fence.",
        ids: ["79", "237", "239", "240", "218"]
    },
    "html-inline": {
        text: "Raw HTML is sanitised tag by tag in place (MdHtml): no HTML block suspends Markdown, tags off the allow list vanish, and Qt draws the rest.",
        ids: ["148", "149", "150", "151", "155", "156", "158", "159", "160", "161", "162", "163", "164", "165", "166", "169", "171", "174", "177", "178", "180", "182", "185", "186", "187", "189", "190", "191", "616", "619", "621", "622", "626", "629", "gfm652", "344", "475", "494"]
    },
    "qt-del": {
        text: "Qt's Markdown import keeps the strikethrough of a raw del tag in some builds and drops it in others, so the example is an exception whichever way it draws.",
        ids: ["167", "168"],
        varies: true
    },
    "link-gate": {
        text: "Only http, https, mailto and relative targets become links and an empty target is no link; any other scheme draws as text.",
        ids: ["596", "598", "599", "601", "485", "486", "567", "200"]
    },
    "gfm-autolink-literals": {
        text: "GFM's autolink extension is on, so a bare address, or one inside angle brackets with a space, links where CommonMark draws text.",
        ids: ["602", "608", "611", "612"]
    },
    "image-sandbox": {
        text: "An image draws only from inside the document folder: an absolute path or a URL draws as alt text or the remote-image placeholder.",
        ids: ["572", "574", "575", "579", "581", "582", "583", "584", "585", "586", "587", "588", "589", "591"]
    },
    "qt-entities": {
        text: "Qt's importer decodes text character references itself: its named table is shorter than HTML5's and it does not substitute a null or newline reference.",
        ids: ["25", "26", "39"]
    },
    "qt-tabs": {
        text: "Qt's importer drops the columns left over when a tab only partly indents code inside a container.",
        ids: ["5", "6", "7"]
    },
    "qt-nested": {
        text: "Qt's importer exports a block nested in an item (a quote, a second paragraph, the text after a heading) beside the item, so the harness cannot read it back inside.",
        ids: ["259", "292", "293", "300"]
    },
    "one-line-forms": {
        text: "A definition's label or title is read from one line, and an inline destination stays on the line of its link.",
        ids: ["196", "208", "510", "541"]
    },
    "empty-item": {
        text: "An item that opens on a blank line keeps the paragraph after a further blank line (MdBlocks does not end it).",
        ids: ["280"]
    },
    "ragged-table": {
        text: "A table row with more cells than the header widens the table, so no cell is hidden; GFM drops the extra cells.",
        ids: ["gfm204"]
    }
}

var ruleOf = {}
for (var rule in RULES) {
    for (var i = 0; i < RULES[rule].ids.length; i++)
        ruleOf[RULES[rule].ids[i]] = rule
}

// The rule that explains this example, or "" when none does.
function exceptionFor(example) {
    return ruleOf.hasOwnProperty(String(example.example)) ? ruleOf[String(example.example)] : ""
}
