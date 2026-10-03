.pragma library

var STRING_METHODS = ["charAt", "charCodeAt", "indexOf", "lastIndexOf", "slice", "substring",
    "match", "replace", "split", "search", "trim", "toLowerCase", "toUpperCase", "repeat"]
var REGEX_METHODS = ["exec", "test"]
var ARRAY_METHODS = ["slice", "join", "map"]
var CONSTANT_TIME_METHODS = ["push", "pop", "hasOwnProperty"]
var CONSTANT_TIME_CALLS = ["Math.max", "Math.min", "String.fromCharCode", "String.fromCodePoint"]
// This local writer method runs parser functions whose internal operations are instrumented.
var PARSER_OBJECT_CALLS = ["writer.finish"]
var COMMENT_PREFIX_LENGTH = "//".length
var work = 0

// Sample input: (/["/*]/, text.slice(0) / scale, text.untrackedScan()).
function stripLiterals(code) {
    var out = []
    var kept = 0
    var i = 0
    var canRegex = true
    var token = ""
    var controlParens = []
    while (i < code.length) {
        var c = code.charAt(i)
        var next = code.charAt(i + 1)
        if (/\s/.test(c)) {
            i++
            continue
        }
        var start = i
        var comment = c === "/" && (next === "/" || next === "*")
        var literal = c === '"' || c === "'" || (c === "/" && canRegex && !comment)
        if (comment || literal) {
            if (comment) {
                var end = next === "/" ? code.indexOf("\n", i + COMMENT_PREFIX_LENGTH)
                    : code.indexOf("*/", i + COMMENT_PREFIX_LENGTH)
                i = end < 0 ? code.length : end + (next === "/" ? 0 : "*/".length)
            } else {
                var inClass = false
                i++
                while (i < code.length) {
                    var ch = code.charAt(i)
                    i++
                    if (ch === "\\") {
                        i++
                        continue
                    }
                    if (c === "/" && ch === "[")
                        inClass = true
                    else if (c === "/" && ch === "]")
                        inClass = false
                    else if (ch === c && !inClass)
                        break
                }
                if (c === "/") {
                    while (/[A-Za-z]/.test(code.charAt(i)) && i < code.length)
                        i++
                }
                canRegex = false
                token = ""
            }
            out.push(code.slice(kept, start))
            out.push(" ")
            kept = i
            continue
        }
        if (c === "`")
            throw new Error("unsupported template literal in parser coverage")
        if (/[A-Za-z0-9_$]/.test(c)) {
            i++
            while (/[A-Za-z0-9_$]/.test(code.charAt(i)) && i < code.length)
                i++
            token = code.slice(start, i)
            canRegex = /^(return|throw|case|delete|void|typeof|new|in|instanceof|yield|await|else|do)$/.test(token)
            continue
        }
        if (c === "(")
            controlParens.push(/^(if|while|for|with|switch|catch)$/.test(token))
        if (c === ")")
            canRegex = controlParens.pop() === true
        else if (c === "]" || c === "}" || c === ".")
            canRegex = false
        else if ((c === "+" || c === "-") && next === c)
            i++
        else
            canRegex = true
        token = ""
        i++
    }
    out.push(code.slice(kept))
    return out.join("")
}

// Sample input: text.substring(i).lastIndexOf("z"), or Leaf.tableBlock(...).
function checkMethods(code, aliases, name) {
    code = stripLiterals(code)
    var calls = /([A-Za-z_$][\w$]*)?\.\s*([A-Za-z_$][\w$]*)\s*\(/g
    var match
    while ((match = calls.exec(code)) !== null) {
        var receiver = match[1] || ""
        var method = match[2]
        if (aliases.indexOf(receiver) >= 0 || STRING_METHODS.indexOf(method) >= 0
            || REGEX_METHODS.indexOf(method) >= 0 || ARRAY_METHODS.indexOf(method) >= 0
            || CONSTANT_TIME_METHODS.indexOf(method) >= 0
            || CONSTANT_TIME_CALLS.indexOf(receiver + "." + method) >= 0
            || PARSER_OBJECT_CALLS.indexOf(receiver + "." + method) >= 0)
            continue
        throw new Error("uncounted parser method " + name + ": " + method)
    }
}

function instrument(code, aliases, name) {
    if (/^Md[^/]*\.js$/.test(name))
        checkMethods(code, aliases, name)
    var counted = STRING_METHODS.concat(REGEX_METHODS, ARRAY_METHODS)
    var calls = new RegExp("\\.\\s*(" + counted.join("|") + ")\\s*\\(", "g")
    return code.replace(calls, function (_, method) { return ".counted_" + method + "(" })
}

function checkFiles(args, readSource) {
    var checked = 0
    for (var i = 0; i < args.length; i++) {
        if (!/^ui\/js\/Md[^/]*\.js$/.test(args[i]))
            continue
        var code = readSource("../" + args[i])
        if (code.length === 0)
            throw new Error("empty parser source " + args[i])
        var aliases = []
        // Sample input: .import "MdLeaf.js" as Leaf.
        var imports = /^\.import "[^"]+" as (\w+)\s*$/gm
        var match
        while ((match = imports.exec(code)) !== null)
            aliases.push(match[1])
        checkMethods(code, aliases, args[i])
        checked++
    }
    if (checked === 0)
        throw new Error("no Md parser files supplied for static coverage")
    return checked
}

function install() {
    for (var i = 0; i < STRING_METHODS.length; i++) {
        var method = STRING_METHODS[i]
        String.prototype["counted_" + method] = (function (original, method) {
            return function () {
                var result = original.apply(this, arguments)
                if (method === "indexOf") {
                    var from = Math.max(0, Math.min(this.length, Number(arguments[1]) || 0))
                    work += result < 0 ? this.length - from
                        : result - from + String(arguments[0]).length
                } else if (method === "lastIndexOf") {
                    var last = arguments[1] === undefined ? this.length : Number(arguments[1])
                    var end = Math.max(0, Math.min(this.length, last))
                    work += result < 0 ? end + 1 : end - result + String(arguments[0]).length
                } else {
                    work += method === "slice" || method === "substring" || method === "repeat" ? result.length
                        : method === "charAt" || method === "charCodeAt" ? 1 : this.length
                }
                return result
            }
        })(String.prototype[method], method)
    }
    for (var r = 0; r < REGEX_METHODS.length; r++) {
        var regexMethod = REGEX_METHODS[r]
        RegExp.prototype["counted_" + regexMethod] = (function (original) {
            return function (text) {
                work += String(text).length
                return original.apply(this, arguments)
            }
        })(RegExp.prototype[regexMethod])
    }
    for (var a = 0; a < ARRAY_METHODS.length; a++) {
        var arrayMethod = ARRAY_METHODS[a]
        Array.prototype["counted_" + arrayMethod] = (function (original, method) {
            return function () {
                var result = original.apply(this, arguments)
                work += method === "join" ? this.length + result.length : result.length
                return result
            }
        })(Array.prototype[arrayMethod], arrayMethod)
    }
}

function uninstall() {
    for (var i = 0; i < STRING_METHODS.length; i++)
        delete String.prototype["counted_" + STRING_METHODS[i]]
    for (var r = 0; r < REGEX_METHODS.length; r++)
        delete RegExp.prototype["counted_" + REGEX_METHODS[r]]
    for (var a = 0; a < ARRAY_METHODS.length; a++)
        delete Array.prototype["counted_" + ARRAY_METHODS[a]]
}
