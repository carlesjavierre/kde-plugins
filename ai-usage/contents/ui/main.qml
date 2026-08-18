import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    property var providers: []
    property bool loading: false
    // kpackagetool installs scripts alongside ui/ inside the package
    readonly property string scriptPath: Qt.resolvedUrl("../scripts/fetch-usage.py").toString().replace("file://", "")

    toolTipMainText: i18n("AI Usage")
    toolTipSubText: {
        var lines = []
        for (var i = 0; i < providers.length; i++) {
            var p = providers[i]
            if (p.error) {
                lines.push(p.name + ": " + i18n("error – %1", p.error))
                continue
            }
            for (var j = 0; j < p.limits.length; j++) {
                var l = p.limits[j]
                var line = p.name + " " + l.label + ": " + l.percent + "%"
                if (l.resets_at)
                    line += i18n(" (resets %1)", new Date(l.resets_at * 1000).toLocaleString(Qt.locale(), Locale.ShortFormat))
                lines.push(line)
            }
        }
        return lines.length > 0 ? lines.join("\n") : i18n("Loading…")
    }

    function usageColor(percent) {
        if (percent >= 90)
            return Kirigami.Theme.negativeTextColor
        if (percent >= 70)
            return Kirigami.Theme.neutralTextColor
        return Kirigami.Theme.textColor
    }

    onExpandedChanged: if (expanded) refresh()

    function limitKey(providerId, label) {
        return providerId + "|" + label
    }

    function isShown(providerId, label) {
        return plasmoid.configuration.shownLimits.indexOf(limitKey(providerId, label)) !== -1
    }

    function toggleShown(providerId, label) {
        var list = plasmoid.configuration.shownLimits.slice()
        var idx = list.indexOf(limitKey(providerId, label))
        if (idx === -1)
            list.push(limitKey(providerId, label))
        else
            list.splice(idx, 1)
        plasmoid.configuration.shownLimits = list
    }

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source)
            root.loading = false
            try {
                root.providers = JSON.parse(data.stdout).providers
            } catch (e) {
                console.warn("ai-usage: failed to parse fetcher output:", e)
            }
        }
    }

    function refresh() {
        if (root.loading)
            return
        root.loading = true
        executable.connectSource("python3 '" + scriptPath + "'")
    }

    Timer {
        interval: plasmoid.configuration.refreshInterval * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    compactRepresentation: MouseArea {
        onClicked: root.expanded = !root.expanded

        Layout.preferredWidth: compactRow.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.minimumWidth: Layout.preferredWidth

        RowLayout {
            id: compactRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            PC3.Label {
                visible: root.providers.length === 0
                text: root.loading ? "…" : "—"
            }

            Repeater {
                model: root.providers
                delegate: RowLayout {
                    id: compactProvider
                    required property var modelData
                    spacing: Math.round(Kirigami.Units.smallSpacing / 2)

                    // Limits ticked for panel display in the popup's checkboxes
                    property var shown: {
                        var out = []
                        var limits = modelData.limits || []
                        for (var i = 0; i < limits.length; i++) {
                            if (root.isShown(modelData.id, limits[i].label))
                                out.push(limits[i])
                        }
                        return out
                    }
                    visible: shown.length > 0 || !!modelData.error

                    Kirigami.Icon {
                        source: Qt.resolvedUrl("../images/" + compactProvider.modelData.id + ".svg")
                        isMask: true
                        color: Kirigami.Theme.textColor
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    }

                    PC3.Label {
                        textFormat: Text.StyledText
                        text: {
                            if (compactProvider.modelData.error)
                                return "<font color='" + Kirigami.Theme.negativeTextColor + "'>!</font>"
                            var parts = []
                            for (var i = 0; i < compactProvider.shown.length; i++) {
                                var l = compactProvider.shown[i]
                                parts.push("<font color='" + root.usageColor(l.percent) + "'>" + l.percent + "%</font>")
                            }
                            return parts.join("·")
                        }
                    }
                }
            }
        }
    }

    fullRepresentation: Item {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 18
        Layout.preferredHeight: mainColumn.implicitHeight + Kirigami.Units.largeSpacing * 4
        Layout.minimumWidth: Layout.preferredWidth
        Layout.minimumHeight: Layout.preferredHeight
        Layout.maximumWidth: Layout.preferredWidth
        Layout.maximumHeight: Layout.preferredHeight

        ColumnLayout {
            id: mainColumn
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing * 2
            spacing: Kirigami.Units.largeSpacing

            Repeater {
                model: root.providers
                delegate: ColumnLayout {
                    id: providerBlock
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Heading {
                        level: 3
                        text: providerBlock.modelData.name
                    }

                    PC3.Label {
                        visible: !!providerBlock.modelData.error
                        text: providerBlock.modelData.error || ""
                        color: Kirigami.Theme.negativeTextColor
                        font: Kirigami.Theme.smallFont
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    Repeater {
                        model: providerBlock.modelData.limits
                        delegate: RowLayout {
                            id: limitRow
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            PC3.CheckBox {
                                checked: root.isShown(providerBlock.modelData.id, limitRow.modelData.label)
                                onToggled: root.toggleShown(providerBlock.modelData.id, limitRow.modelData.label)
                                PC3.ToolTip.text: i18n("Show in panel")
                                PC3.ToolTip.visible: hovered
                            }

                            PC3.Label {
                                text: limitRow.modelData.label
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                                elide: Text.ElideRight
                            }
                            PC3.ProgressBar {
                                from: 0
                                to: 100
                                value: limitRow.modelData.percent
                                Layout.fillWidth: true
                            }
                            PC3.Label {
                                text: limitRow.modelData.percent + "%"
                                color: root.usageColor(limitRow.modelData.percent)
                                horizontalAlignment: Text.AlignRight
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 2
                            }
                            PC3.Label {
                                visible: !!limitRow.modelData.resets_at
                                text: limitRow.modelData.resets_at
                                      ? new Date(limitRow.modelData.resets_at * 1000)
                                            .toLocaleString(Qt.locale(), "ddd hh:mm")
                                      : ""
                                opacity: 0.7
                                font: Kirigami.Theme.smallFont
                            }
                        }
                    }
                }
            }
        }

        PC3.ToolButton {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Kirigami.Units.largeSpacing
            icon.name: "view-refresh"
            enabled: !root.loading
            onClicked: root.refresh()
            display: PC3.AbstractButton.IconOnly
            text: i18n("Refresh")
            PC3.ToolTip.text: text
            PC3.ToolTip.visible: hovered
        }
    }
}
