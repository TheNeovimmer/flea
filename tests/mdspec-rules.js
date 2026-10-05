.pragma library

// The deliberate differences from the spec, each with its rule; an example the parser now draws right fails as stale.
var RULES = {
    "html-inline": {
        text: "Raw HTML is sanitised tag by tag in place (MdHtml): no HTML block suspends Markdown, tags off the allow list vanish, and Qt draws the rest.",
        ids: ["148", "149", "150", "151", "155", "156", "158", "159", "160", "161", "162", "163", "164", "165", "166", "169", "171", "174", "177", "178", "180", "182", "185", "186", "187", "189", "190", "191", "616", "619", "621", "622", "626", "629", "gfm652", "344", "475", "494"]
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
