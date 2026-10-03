import Quickshell.Io

FileView {
    id: memory
    printErrors: false
    // Each stamp belongs to a completed reload, including the write/read check.
    property int readSequence: 0
    readonly property int firstPssKb: 111
    readonly property int secondPssKb: 222
    readonly property int firstAnonymousKb: 333
    readonly property int secondAnonymousKb: 444
    readonly property int firstRssKb: 555
    readonly property int secondRssKb: 666

    function readText(path) {
        memory.path = path;
        memory.reload();
        memory.waitForJob();
        var contents = memory.text();
        memory.readSequence++;
        return contents;
    }

    // Sample inputs: "Pss: 45120 kB" in smaps_rollup, "VmHWM: 41380 kB" in a process status file.
    function memField(path, key) {
        return memory.memValue(memory.readText(path), key);
    }

    function snapshot(path) {
        var contents = memory.readText(path);
        return { pss: memory.memValue(contents, "Pss"),
            rss: memory.memValue(contents, "Rss"),
            anonymous: memory.memValue(contents, "Anonymous"), readSequence: memory.readSequence };
    }

    function checkReload(path, writePhase, check, then) {
        writePhase("Pss: " + memory.firstPssKb + " kB\nAnonymous: " + memory.firstAnonymousKb
            + " kB\nRss: " + memory.firstRssKb + " kB", function () {
            var first = memory.snapshot(path);
            writePhase("Pss: " + memory.secondPssKb + " kB\nAnonymous: " + memory.secondAnonymousKb
                + " kB\nRss: " + memory.secondRssKb + " kB", function () {
                var second = memory.snapshot(path);
                check(first.pss === memory.firstPssKb && second.pss === memory.secondPssKb
                    && first.anonymous === memory.firstAnonymousKb && second.anonymous === memory.secondAnonymousKb
                    && first.rss === memory.firstRssKb && second.rss === memory.secondRssKb
                    && second.readSequence === first.readSequence + 1,
                    "memory reader reloads all three fields in one stamped read after its contents change");
                then();
            });
        });
    }

    // Sample input: "Pss: 45120 kB\nAnonymous: 32200 kB\nRss: 60100 kB\n" from smaps_rollup.
    function memValue(contents, key) {
        var lines = contents.split("\n");
        for (var i = 0; i < lines.length; i++) {
            var cut = lines[i].split(":");
            if (cut.length >= 2 && cut[0] === key)
                return parseInt(cut[1], 10);
        }
        return -1;
    }

    // The pid belongs to bwrap, so find qjs's peak below it in the process tree.
    function treePeak(pid) {
        var best = memory.memField("/proc/" + pid + "/status", "VmHWM");
        // Sample input: "1234 5678 " from /proc/<pid>/task/<pid>/children.
        var kids = memory.readText("/proc/" + pid + "/task/" + pid + "/children").trim().split(/\s+/);
        for (var i = 0; i < kids.length; i++) {
            if (kids[i].length > 0)
                best = Math.max(best, memory.treePeak(kids[i]));
        }
        return best;
    }
}
