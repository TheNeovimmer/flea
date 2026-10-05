.import "../../ui/js/Columns.js" as Columns
.import "sourcefixture.js" as Source

// The backend watches exactly the column directories drawn: every peek names them, and a column that comes back is asked again.
function run(check) {
    var keep = { drawn: [] }
    var asked = function (plan) { return plan.map(function (one) { return one.path + ":" + one.again }).join("|") }
    check("a first refresh asks every column, ancestors then the child", asked(Columns.keepAsks(keep, ["/a", "/a/b"], "/a/b/c")), "/a:true|/a/b:true|/a/b/c:true")
    check("and draws exactly those", keep.drawn.join("|"), "/a|/a/b|/a/b/c")
    check("a column still drawn is asked as before", asked(Columns.keepAsks(keep, ["/a", "/a/b"], "/a/b/d")), "/a:false|/a/b:false|/a/b/d:true")
    check("the child that left is no longer drawn", keep.drawn.join("|"), "/a|/a/b|/a/b/d")
    check("a file under the cursor draws no child column", asked(Columns.keepAsks(keep, ["/a", "/a/b"], "")), "/a:false|/a/b:false")
    check("a column that scrolled away and returns is asked again", asked(Columns.keepAsks(keep, ["/a", "/a/b"], "/a/b/d")), "/a:false|/a/b:false|/a/b/d:true")
    check("a narrow window with no folder under the cursor draws nothing", Columns.keepAsks({ drawn: [] }, [], "").length, 0)
    check("a child that is also an ancestor is named once", Columns.keepAsks({ drawn: [] }, ["/a"], "/a").length, 1)
    var area = Source.source("ui/ColumnsArea.qml")
    var refreshBody = Source.slice(area, "function refreshNeighbours", "function askMeta")
    check("refresh asks from the keep plan", refreshBody.indexOf("Columns.keepAsks(root.keep, Columns.neighbourAsks(root.pane.path, root.width, root.columnsLimit), root.childPath)") >= 0
        && refreshBody.indexOf("root.ask(one.path, one.again)") >= 0, true)
    check("every column peek carries the drawn set", Source.slice(area, "function ask(path, again)", "// Hidden view asks nothing")
        .indexOf("root.pane.showHidden, undefined, root.keep.drawn)") >= 0, true)
    check("the wire carries it as keep", Source.source("ui/Backend.qml").indexOf("watch: Array.isArray(keep), keep: keep") >= 0, true)
}
