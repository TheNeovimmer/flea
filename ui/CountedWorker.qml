import QtQuick
import QtCore

// Says WORKER_STARTED under flea.worker (off unless QT_LOGGING_RULES names it), so log checks match Qt 6.11.2's one null connect warning per start.
WorkerScript {
    property QtObject startLog: LoggingCategory { name: "flea.worker"; defaultLogLevel: LoggingCategory.Warning }
    Component.onCompleted: if (source.toString() !== "") console.info(startLog, "WORKER_STARTED " + source)
}
