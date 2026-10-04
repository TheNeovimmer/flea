.pragma library

// MdEntity: backslash escapes and character references inside a link destination or an info string, which no renderer reads for us.
var REPLACEMENT_CHARACTER = 0xfffd
var MAX_CODE_POINT = 0x10ffff
var LATIN1_START = 0xa0
var LATIN1_NAMES = ("nbsp iexcl cent pound curren yen brvbar sect uml copy ordf laquo not shy reg macr deg plusmn sup2 sup3 acute micro para "
    + "middot cedil sup1 ordm raquo frac14 frac12 frac34 iquest Agrave Aacute Acirc Atilde Auml Aring AElig Ccedil Egrave Eacute Ecirc "
    + "Euml Igrave Iacute Icirc Iuml ETH Ntilde Ograve Oacute Ocirc Otilde Ouml times Oslash Ugrave Uacute Ucirc Uuml Yacute THORN szlig "
    + "agrave aacute acirc atilde auml aring aelig ccedil egrave eacute ecirc euml igrave iacute icirc iuml eth ntilde ograve oacute ocirc "
    + "otilde ouml divide oslash ugrave uacute ucirc uuml yacute thorn yuml").split(" ")
var NAMED = { amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'" }
for (var n = 0; n < LATIN1_NAMES.length; n++)
    NAMED[LATIN1_NAMES[n]] = String.fromCharCode(LATIN1_START + n)
var REFERENCE = /\\([!-\/:-@\[-`{-~])|&(?:#([0-9]{1,7})|#[xX]([0-9a-fA-F]{1,6})|([A-Za-z][A-Za-z0-9]{1,31}));/g

// Sample input: "f&ouml;o\*" answers "föo*"; an unknown name such as "&nosuch;" stays as written.
function decodeReferences(text) {
    if (text.indexOf("\\") < 0 && text.indexOf("&") < 0)
        return text
    return text.replace(REFERENCE, function (all, escaped, dec, hex, name) {
        if (escaped !== undefined)
            return escaped
        if (name !== undefined)
            return NAMED.hasOwnProperty(name) ? NAMED[name] : all
        var code = dec !== undefined ? parseInt(dec, 10) : parseInt(hex, 16)
        return String.fromCodePoint(code > 0 && code <= MAX_CODE_POINT ? code : REPLACEMENT_CHARACTER)
    })
}
