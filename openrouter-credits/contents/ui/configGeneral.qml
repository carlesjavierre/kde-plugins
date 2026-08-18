import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_apiKey: apiKey.text
    property alias cfg_refreshInterval: refreshInterval.value

    // Plasma's config system reads these to enable "reset to defaults"
    property string cfg_apiKeyDefault: ""
    property int cfg_refreshIntervalDefault: 300

    Kirigami.FormLayout {
        QQC2.TextField {
            id: apiKey
            Kirigami.FormData.label: i18n("Management key:")
            echoMode: TextInput.Password
        }

        QQC2.SpinBox {
            id: refreshInterval
            Kirigami.FormData.label: i18n("Refresh every:")
            from: 60
            to: 86400
            stepSize: 60
            textFromValue: (value) => i18np("%1 minute", "%1 minutes", Math.round(value / 60))
            valueFromText: (text) => parseInt(text) * 60
        }

        QQC2.Label {
            text: i18n("From openrouter.ai/settings/management-keys. The credits endpoint rejects normal inference keys (openrouter.ai/settings/keys) with a 403.")
            wrapMode: Text.Wrap
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
            font: Kirigami.Theme.smallFont
        }
    }
}
