import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    property real remaining: NaN
    property real used: NaN
    property string errorText: ""
    property string lastUpdated: ""

    // Rolling 24h via POST /api/v1/analytics/query. granularity is optional,
    // and omitting it aggregates over the whole range — which is what we want,
    // since cache_hit_rate is a rate and must not be summed across buckets.
    property var topModels: []
    property real tokensTotal: NaN
    property real cacheHitRate: NaN
    readonly property real topMax: topModels.length > 0 ? topModels[0].usage : 0

    function fmtTokens(n) {
        if (isNaN(n)) {
            return "—"
        }
        if (n >= 1e9) {
            return (n / 1e9).toFixed(2) + "B"
        }
        if (n >= 1e6) {
            return (n / 1e6).toFixed(2) + "M"
        }
        if (n >= 1e3) {
            return (n / 1e3).toFixed(1) + "k"
        }
        return n.toFixed(0)
    }

    readonly property string display: errorText !== "" ? "—"
        : isNaN(remaining) ? "…"
        : "$" + remaining.toFixed(2)

    // ponytail: key lives in plaintext in the plasma applet config; move to
    // KWallet (org.kde.kwallet DBus) if this machine is shared.
    function refresh() {
        const key = Plasmoid.configuration.apiKey
        if (!key) {
            errorText = i18n("No API key configured")
            return
        }
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) {
                return
            }
            if (xhr.status !== 200) {
                errorText = xhr.status === 0 ? i18n("Network error")
                    : xhr.status === 401 ? i18n("Key rejected")
                    : xhr.status === 403 ? i18n("Key lacks permission for /credits")
                    : i18n("HTTP %1", xhr.status)
                return
            }
            try {
                const d = JSON.parse(xhr.responseText).data
                remaining = d.total_credits - d.total_usage
                used = d.total_usage
                errorText = ""
                lastUpdated = new Date().toLocaleTimeString(Qt.locale(), "HH:mm")
            } catch (e) {
                errorText = i18n("Unexpected response")
            }
        }
        xhr.open("GET", "https://openrouter.ai/api/v1/credits")
        xhr.setRequestHeader("Authorization", "Bearer " + key)
        xhr.send()
        refreshActivity()
    }

    function queryAnalytics(body, onRows) {
        const key = Plasmoid.configuration.apiKey
        if (!key) {
            return
        }
        const now = new Date()
        body.timeRange = {
            start: new Date(now.getTime() - 24 * 60 * 60 * 1000).toISOString(),
            end: now.toISOString()
        }
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE || xhr.status !== 200) {
                return
            }
            try {
                const payload = JSON.parse(xhr.responseText)
                onRows((payload.data && payload.data.data) || [])
            } catch (e) {
                // leave previous values in place
            }
        }
        xhr.open("POST", "https://openrouter.ai/api/v1/analytics/query")
        xhr.setRequestHeader("Authorization", "Bearer " + key)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.send(JSON.stringify(body))
    }

    function refreshActivity() {
        // Summary: no dimensions, no granularity -> one aggregated row.
        queryAnalytics({
            metrics: ["tokens_total", "cache_hit_rate"]
        }, function (rows) {
            const r = rows.length > 0 ? rows[0] : {}
            tokensTotal = Number(r.tokens_total)
            const rate = Number(r.cache_hit_rate)
            // display_format is "percent"; accept either 0-1 or 0-100.
            cacheHitRate = isNaN(rate) ? NaN : (rate <= 1 ? rate * 100 : rate)
        })

        // Per model, ranked by spend.
        queryAnalytics({
            metrics: ["total_usage"],
            dimensions: ["model"],
            limit: 100
        }, function (rows) {
            const arr = []
            for (let i = 0; i < rows.length; i++) {
                const usage = Number(rows[i].total_usage)
                if (rows[i].model && usage > 0) {
                    arr.push({ model: rows[i].model, usage: usage })
                }
            }
            arr.sort(function (a, b) { return b.usage - a.usage })
            topModels = arr.slice(0, 6)
        })
    }

    Timer {
        id: refreshTimer
        interval: Plasmoid.configuration.refreshInterval * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // A real QML property binding: changing the key in settings re-evaluates
    // this and fires onApiKeyChanged. (Plasmoid.configuration is a property
    // map and does not reliably emit per-key signals to a Connections block.)
    readonly property string apiKey: Plasmoid.configuration.apiKey
    onApiKeyChanged: refreshTimer.restart()

    toolTipMainText: i18n("OpenRouter credits")
    toolTipSubText: errorText !== "" ? errorText
        : isNaN(remaining) ? i18n("Loading…")
        : i18n("%1 remaining, %2 used", display, "$" + used.toFixed(2))

    // The root must be a plain Item, not a Layout: the panel reads Layout.*
    // hints off it, and binding those to a Layout's own implicitWidth is
    // self-referential.
    compactRepresentation: Item {
        id: compactRoot

        readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

        Layout.minimumWidth: vertical ? 0 : row.implicitWidth
        Layout.preferredWidth: Layout.minimumWidth
        Layout.minimumHeight: vertical ? row.implicitHeight : 0

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: Qt.resolvedUrl("../images/openrouter.png")
                Layout.preferredHeight: Math.min(compactRoot.height,
                                                 Kirigami.Units.iconSizes.small)
                Layout.preferredWidth: Layout.preferredHeight
            }

            PlasmaComponents3.Label {
                text: root.display
                color: root.errorText !== "" ? Kirigami.Theme.negativeTextColor
                                             : Kirigami.Theme.textColor
                verticalAlignment: Text.AlignVCenter
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.expanded = !root.expanded
        }
    }

    fullRepresentation: ColumnLayout {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.preferredWidth: Kirigami.Units.gridUnit * 18
        Layout.maximumWidth: Kirigami.Units.gridUnit * 18

        // Pin the popup to its content: without a preferred/maximum height
        // Plasma gives the popup a default size much taller than this content,
        // and the trailing spacer soaks up the difference.
        Layout.minimumHeight: implicitHeight
        Layout.preferredHeight: implicitHeight
        Layout.maximumHeight: implicitHeight

        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: Qt.resolvedUrl("../images/openrouter.png")
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredWidth: Layout.preferredHeight
            }

            PlasmaComponents3.Label {
                text: i18n("OpenRouter")
                font.bold: true
                Layout.fillWidth: true
            }
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: root.errorText !== "" ? root.errorText
                : isNaN(root.remaining) ? i18n("Loading…")
                : root.display
            color: root.errorText !== "" ? Kirigami.Theme.negativeTextColor
                                         : Kirigami.Theme.textColor
            font.pointSize: root.errorText !== "" ? Kirigami.Theme.defaultFont.pointSize
                                                  : Kirigami.Theme.defaultFont.pointSize * 2
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            visible: !isNaN(root.used)
            opacity: 0.7
            font: Kirigami.Theme.smallFont
            text: root.lastUpdated === ""
                ? i18n("%1 used", "$" + root.used.toFixed(2))
                : i18n("%1 used · updated %2", "$" + root.used.toFixed(2), root.lastUpdated)
        }

        Kirigami.Separator {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing
        }

        // Two stat tiles: single headline numbers, no plot needed.
        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.largeSpacing

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                PlasmaComponents3.Label {
                    text: i18n("Token volume")
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                }
                PlasmaComponents3.Label {
                    text: root.fmtTokens(root.tokensTotal)
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                PlasmaComponents3.Label {
                    text: i18n("Cache hit rate")
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                }
                PlasmaComponents3.Label {
                    text: isNaN(root.cacheHitRate) ? "—"
                                                   : root.cacheHitRate.toFixed(1) + "%"
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
                }
            }
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("Top models by spend · last 24 hours")
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            visible: root.topModels.length === 0
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            wrapMode: Text.Wrap
            text: i18n("No usage recorded")
        }

        // One series (spend) across 3 named bars: direct labels, no legend,
        // one hue from the Plasma theme rather than colour-by-rank.
        Repeater {
            model: root.topModels

            delegate: ColumnLayout {
                required property var modelData

                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: modelData.model
                        elide: Text.ElideMiddle
                        font: Kirigami.Theme.smallFont
                    }

                    PlasmaComponents3.Label {
                        text: "$" + modelData.usage.toFixed(2)
                        font: Kirigami.Theme.smallFont
                        opacity: 0.8
                    }
                }

                // Layouts drive height from Layout.preferredHeight; a plain
                // `height` here is ignored and the row inflates.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 4
                    radius: 2
                    color: Kirigami.Theme.alternateBackgroundColor

                    Rectangle {
                        width: root.topMax > 0
                            ? Math.max(parent.width * (modelData.usage / root.topMax), 2 * radius)
                            : 0
                        height: parent.height
                        radius: 2
                        color: Kirigami.Theme.highlightColor
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing

            PlasmaComponents3.Button {
                text: i18n("Refresh")
                icon.name: "view-refresh"
                onClicked: root.refresh()
            }

            Item { Layout.fillWidth: true }

            PlasmaComponents3.Label {
                text: "<a href=\"https://openrouter.ai/credits\">OpenRouter ↗</a>"
                textFormat: Text.StyledText
                onLinkActivated: link => Qt.openUrlExternally(link)

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    cursorShape: Qt.PointingHandCursor
                }
            }
        }
    }
}
