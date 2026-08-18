import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_refreshInterval: refreshSpin.value

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: refreshSpin
            Kirigami.FormData.label: i18n("Refresh interval:")
            from: 60
            to: 86400
            stepSize: 60
            textFromValue: (value) => i18np("%1 minute", "%1 minutes", Math.round(value / 60))
            valueFromText: (text) => parseInt(text) * 60
        }

        QQC2.Label {
            text: i18n("Claude usage is read from ~/.claude/.credentials.json.\nCodex usage is read from ~/.codex/auth.json.\nOpenCode usage is read from ~/.local/share/opencode/auth.json.\n\nFaster polling might result in 429 (rate limit) errors.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }
    }
}
