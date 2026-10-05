// Compiles the vendored bundles to bytecode inside the compile jail: figure-compile.mjs VENDOR_DIR OUT_DIR, one exclusive file per bundle.
import * as std from "qjs:std";
import * as os from "qjs:os";
import { BUNDLES, compileBundle } from "./figure-bytecode.mjs";

var FILE_MODE = 0o600;

function writeNew(path, buffer) {
    var fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, FILE_MODE);
    if (fd < 0)
        throw new Error("could not create " + path);
    var bytes = new Uint8Array(buffer);
    var done = 0;
    while (done < bytes.length) {
        var n = os.write(fd, buffer, done, bytes.length - done);
        if (n <= 0) {
            os.close(fd);
            throw new Error("could not write " + path);
        }
        done += n;
    }
    os.close(fd);
}

var vendor = scriptArgs[1];
var out = scriptArgs[2];
for (var kind of Object.keys(BUNDLES)) {
    var spec = BUNDLES[kind];
    var text = std.loadFile(vendor + "/" + spec.file);
    if (text === null)
        throw new Error("could not read " + spec.file);
    writeNew(out + "/" + spec.blob, compileBundle(text, spec.global));
}
