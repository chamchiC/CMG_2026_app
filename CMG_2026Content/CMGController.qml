import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: controller
    width: 500
    height: 750
    color: "#f0f0f0"

    property real rollAngleValue: 0.0
    property real gimbalAngleValue: 0.0
    property real rollVelocityValue: 0.0
    property real gimbalVelocityValue: 0.0
    property real torqueValue: 0.0

    property bool lampGimbalMotor: false
    property bool lampAngleSensor: false
    property bool lampWheelMotor: false
    property bool lampRPM1Sensor: false
    property bool lampRPM2Sensor: false
    property bool lampMainLoop: false
    property bool lampStable: false
    property bool lampStandard: false
    property bool lampPerformance: false

    signal startClicked()
    signal stopClicked()
    signal resetClicked()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 10

        Text {
            text: "Graph Value Controller"
            font.pixelSize: 22; font.bold: true; color: "#2c2c54"
            Layout.alignment: Qt.AlignHCenter
        }

        Rectangle { Layout.fillWidth: true; height: 2; color: "#cccccc" }

        GroupBox {
            Layout.fillWidth: true
            title: "Roll Angle (θ)   —   range: -10 ~ 10"
            ColumnLayout {
                anchors.fill: parent; spacing: 5
                RowLayout {
                    Text { text: "Value:"; font.pixelSize: 14 }
                    Text { text: controller.rollAngleValue.toFixed(2); font.pixelSize: 14; font.bold: true; color: "#1a73e8" }
                }
                Slider { Layout.fillWidth: true; from: -10; to: 10; value: 0; stepSize: 0.1; onValueChanged: controller.rollAngleValue = value }
            }
        }

        GroupBox {
            Layout.fillWidth: true
            title: "Gimbal Angle (θ)   —   range: -65 ~ 65"
            ColumnLayout {
                anchors.fill: parent; spacing: 5
                RowLayout {
                    Text { text: "Value:"; font.pixelSize: 14 }
                    Text { text: controller.gimbalAngleValue.toFixed(2); font.pixelSize: 14; font.bold: true; color: "#e8501a" }
                }
                Slider { Layout.fillWidth: true; from: -65; to: 65; value: 0; stepSize: 0.5; onValueChanged: controller.gimbalAngleValue = value }
            }
        }

        GroupBox {
            Layout.fillWidth: true
            title: "Roll Velocity   —   range: -1.0 ~ 1.0"
            ColumnLayout {
                anchors.fill: parent; spacing: 5
                RowLayout {
                    Text { text: "Value:"; font.pixelSize: 14 }
                    Text { text: controller.rollVelocityValue.toFixed(3); font.pixelSize: 14; font.bold: true; color: "#2e7d32" }
                }
                Slider { Layout.fillWidth: true; from: -1.0; to: 1.0; value: 0; stepSize: 0.01; onValueChanged: controller.rollVelocityValue = value }
            }
        }

        GroupBox {
            Layout.fillWidth: true
            title: "Gimbal Velocity   —   range: -1.0 ~ 1.0"
            ColumnLayout {
                anchors.fill: parent; spacing: 5
                RowLayout {
                    Text { text: "Value:"; font.pixelSize: 14 }
                    Text { text: controller.gimbalVelocityValue.toFixed(3); font.pixelSize: 14; font.bold: true; color: "#6a1b9a" }
                }
                Slider { Layout.fillWidth: true; from: -1.0; to: 1.0; value: 0; stepSize: 0.01; onValueChanged: controller.gimbalVelocityValue = value }
            }
        }

        GroupBox {
            Layout.fillWidth: true
            title: "Torque (Nm)   —   range: -1.0 ~ 1.0"
            ColumnLayout {
                anchors.fill: parent; spacing: 5
                RowLayout {
                    Text { text: "Value:"; font.pixelSize: 14 }
                    Text { text: controller.torqueValue.toFixed(3); font.pixelSize: 14; font.bold: true; color: "#c62828" }
                }
                Slider { Layout.fillWidth: true; from: -1.0; to: 1.0; value: 0; stepSize: 0.01; onValueChanged: controller.torqueValue = value }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 2; color: "#cccccc" }

        // ── Communication 램프 제어 ──
        GroupBox {
            Layout.fillWidth: true
            title: "Communication Lamps"
            GridLayout {
                anchors.fill: parent; columns: 3; rowSpacing: 6; columnSpacing: 8
                Button { text: "Gimbal_Motor"; Layout.fillWidth: true; font.pixelSize: 11; palette.button: controller.lampGimbalMotor ? "#4a6741" : "#888"; palette.buttonText: "#fff"; onClicked: controller.lampGimbalMotor = !controller.lampGimbalMotor }
                Button { text: "Angle_Sensor"; Layout.fillWidth: true; font.pixelSize: 11; palette.button: controller.lampAngleSensor ? "#4a6741" : "#888"; palette.buttonText: "#fff"; onClicked: controller.lampAngleSensor = !controller.lampAngleSensor }
                Button { text: "Wheel_Motor"; Layout.fillWidth: true; font.pixelSize: 11; palette.button: controller.lampWheelMotor ? "#4a6741" : "#888"; palette.buttonText: "#fff"; onClicked: controller.lampWheelMotor = !controller.lampWheelMotor }
                Button { text: "RPM1_Sensor"; Layout.fillWidth: true; font.pixelSize: 11; palette.button: controller.lampRPM1Sensor ? "#4a6741" : "#888"; palette.buttonText: "#fff"; onClicked: controller.lampRPM1Sensor = !controller.lampRPM1Sensor }
                Button { text: "RPM2_Sensor"; Layout.fillWidth: true; font.pixelSize: 11; palette.button: controller.lampRPM2Sensor ? "#4a6741" : "#888"; palette.buttonText: "#fff"; onClicked: controller.lampRPM2Sensor = !controller.lampRPM2Sensor }
                Button { text: "Main Loop"; Layout.fillWidth: true; font.pixelSize: 11; palette.button: controller.lampMainLoop ? "#4a6741" : "#888"; palette.buttonText: "#fff"; onClicked: controller.lampMainLoop = !controller.lampMainLoop }
            }
        }

        // ── Control Parameter 램프 제어 ──
        GroupBox {
            Layout.fillWidth: true
            title: "Control Parameter Lamps"
            RowLayout {
                anchors.fill: parent; spacing: 10
                Button { Layout.fillWidth: true; text: "Stable"; font.pixelSize: 12; palette.button: controller.lampStable ? "#4a6741" : "#888"; palette.buttonText: "#fff"; onClicked: controller.lampStable = !controller.lampStable }
                Button { Layout.fillWidth: true; text: "Standard"; font.pixelSize: 12; palette.button: controller.lampStandard ? "#4a6741" : "#888"; palette.buttonText: "#fff"; onClicked: controller.lampStandard = !controller.lampStandard }
                Button { Layout.fillWidth: true; text: "Performance"; font.pixelSize: 12; palette.button: controller.lampPerformance ? "#4a6741" : "#888"; palette.buttonText: "#fff"; onClicked: controller.lampPerformance = !controller.lampPerformance }
            }
        }

        RowLayout {
            Layout.fillWidth: true; spacing: 15
            Button { Layout.fillWidth: true; text: "▶ Start"; font.pixelSize: 16; font.bold: true; onClicked: controller.startClicked() }
            Button { Layout.fillWidth: true; text: "■ Stop"; font.pixelSize: 16; font.bold: true; onClicked: controller.stopClicked() }
            Button { Layout.fillWidth: true; text: "↺ Reset"; font.pixelSize: 16; font.bold: true; onClicked: controller.resetClicked() }
        }
    }
}
