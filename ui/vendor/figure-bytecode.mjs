// The figure bundles as quickjs-ng bytecode: compiled once per engine build, read back instead of parsed; see AGENTS.md "Markdown figures".
import * as std from "qjs:std";
import * as bjson from "qjs:bjson";

// quickjs.h: allow function and module bytecode, and keep the source text out of the blob.
const WRITE_BYTECODE = 1;
const WRITE_STRIP_SOURCE = 16;
const READ_BYTECODE = 1;
const EXPORT_CLAUSE = /^export\s*\{([^}]*)\}\s*;?\s*$/;
const IDENTIFIER = /^[\w$]+$/;

// Each bundle ends in one export clause, so its text becomes a global the module sets: a compiled module has no name to import it by.
export const BUNDLES = {
    math: { file: "math.mjs", blob: "math.bc", global: "__figureMath" },
    mermaid: { file: "mermaid.mjs", blob: "mermaid.bc", global: "__figureMermaid" },
};

// Sample input: "var a=1;export{wgt as mermaidToSvg};" gives "var a=1;globalThis.__figureMermaid={mermaidToSvg:wgt};".
export function exposeExports(text, global) {
    var at = text.lastIndexOf("export");
    var clause = at < 0 ? null : EXPORT_CLAUSE.exec(text.slice(at));
    if (!clause)
        throw new Error("the bundle does not end in one export clause");
    var members = clause[1].split(",").map(function (part) {
        var names = part.trim().split(/\s+as\s+/);
        if (names.length > 2 || !names.every(function (name) { return IDENTIFIER.test(name); }))
            throw new Error("an export the bytecode path cannot name");
        return names[names.length - 1] + ":" + names[0];
    });
    return text.slice(0, at) + "globalThis." + global + "={" + members.join(",") + "};";
}

export function compileBundle(text, global) {
    var code = std.evalScript(exposeExports(text, global), { compile_only: true, compile_module: true });
    return bjson.write(code, WRITE_BYTECODE | WRITE_STRIP_SOURCE);
}

// The caller verified the bytes: bytecode is trusted input to the engine and is never read from an unchecked file.
export async function loadBundle(bytes, global) {
    var module = bjson.read(bytes.buffer, bytes.byteOffset, bytes.length, READ_BYTECODE);
    await std.evalScript(module, { eval_module: true });
    var api = globalThis[global];
    delete globalThis[global];
    if (!api)
        throw new Error("the bytecode set no exports");
    return api;
}

export function readBytes(path) {
    var bytes = std.loadFile(path, { binary: true });
    if (!bytes)
        throw new Error("could not read " + path);
    return bytes;
}
