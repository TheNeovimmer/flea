import QtQuick
import QtCore

// A WorkerScript that says WORKER_STARTED under flea.worker, which logs only when QT_LOGGING_RULES names flea.worker.info.
// Qt 6.11.2 prints one null connect warning for each worker that starts with a source, and a log check counts the two against each other.
WorkerScript {
    property QtObject startLog: LoggingCategory { name: "flea.worker"; defaultLogLevel: LoggingCategory.Warning }
    Component.onCompleted: if (source.toString() !== "") console.info(startLog, "WORKER_STARTED " + source)
}
