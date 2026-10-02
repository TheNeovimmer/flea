.import "../../ui/js/Tabs.js" as Tabs

function run(check) {
    var rect = { x: 100, y: 200, width: 600, height: 400 }
    var band = { x: 16, y: 40, width: 584, height: 32 }
    check("catcher own-strip drop returns at shared insertion index",
          JSON.stringify(Tabs.catcherOutcome(rect, band, 140, 250, 100, 3)),
          JSON.stringify({ outcome: "return", at: 0 }))
    check("catcher own-strip midpoint uses the strip insertion math",
          Tabs.catcherOutcome(rect, band, 266, 250, 100, 3).at, 2)
    check("catcher own-window drop off strip cancels",
          Tabs.catcherOutcome(rect, band, 140, 350, 100, 3).outcome, "cancel")
    check("catcher outside own window tears off",
          Tabs.catcherOutcome(rect, band, 701, 250, 100, 3).outcome, "tearoff")
    check("unknown source rectangle cancels even on desktop",
          Tabs.catcherOutcome(null, band, 900, 900, 100, 3).outcome, "cancel")
    check("left strip margin inside window cancels",
          Tabs.catcherOutcome(rect, band, 105, 250, 100, 3).outcome, "cancel")
    check("strip lower edge belongs to window cancel band",
          Tabs.catcherOutcome(rect, band, 140, 272, 100, 3).outcome, "cancel")
    check("window right edge is outside",
          Tabs.catcherOutcome(rect, band, 700, 250, 100, 3).outcome, "tearoff")
}
