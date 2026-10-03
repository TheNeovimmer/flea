import Quickshell.Io

FileView {
    id: memory
    printErrors: false

    function readText(path) {
        memory.path = path;
        memory.reload();
        memory.waitForJob();
        return memory.text();
    }

    // Sample inputs: "Pss: 45120 kB" in smaps_rollup, "VmHWM: 41380 kB" in a process status file.
    function memField(path, key) {
        var lines = memory.readText(path).split("\n");
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
        var kids = memory.readText("/proc/" + pid + "/task/" + pid + "/children").trim().split(/\s+/);
        for (var i = 0; i < kids.length; i++) {
            if (kids[i].length > 0)
                best = Math.max(best, memory.treePeak(kids[i]));
        }
        return best;
    }
}
