import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCharts

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: "#f0f0f0"

    // ── 데이터 관리 ──
    property real inputValue: 0.0
    property int timeIndex: 0
    property int maxPoints: 200

    // ── 0.1초 타이머 ──
    Timer {
        id: dataTimer
        interval: 100
        running: false
        repeat: true
        onTriggered: {
            lineSeries.append(timeIndex * 0.1, inputValue)

            if (lineSeries.count > maxPoints) {
                lineSeries.remove(0)
            }

            if (timeIndex * 0.1 > axisX.max) {
                axisX.min = timeIndex * 0.1 - 20
                axisX.max = timeIndex * 0.1
            }

            timeIndex++
            timeLabel.text = (timeIndex * 0.1).toFixed(1) + " s"
        }
    }

    // ── 좌측: 그래프 영역 ──
    Rectangle {
        id: graphPanel
        x: 10
        y: 10
        width: 1350
        height: 1060
        color: "#ffffff"
        radius: 4
        border.color: "#3a3a5c"
        border.width: 3

        ChartView {
            id: chartView
            anchors.fill: parent
            anchors.margins: 10
            antialiasing: true
            backgroundColor: "#ffffff"
            title: "Realtime Input Graph"

            legend.visible: true
            legend.alignment: Qt.AlignBottom

            ValuesAxis {
                id: axisX
                min: 0
                max: 20
                tickCount: 11
                titleText: "Time (s)"
                gridLineColor: "#d0d0d0"
            }

            ValuesAxis {
                id: axisY
                min: -100
                max: 100
                tickCount: 11
                titleText: "Value"
                gridLineColor: "#d0d0d0"
            }

            LineSeries {
                id: lineSeries
                name: "Input Value"
                color: "#3a3a5c"
                width: 2
                axisX: axisX
                axisY: axisY
            }
        }
    }

    // ── 우측: 입력 패널 ──
    Rectangle {
        id: inputPanel
        x: 1370
        y: 10
        width: 540
        height: 1060
        color: "#ffffff"
        radius: 4
        border.color: "#3a3a5c"
        border.width: 3

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 30
            spacing: 20

            Text {
                text: "Input Panel"
                font.pixelSize: 28
                font.bold: true
                color: "#3a3a5c"
                Layout.alignment: Qt.AlignHCenter
            }

            Rectangle { Layout.fillWidth: true; height: 2; color: "#d0d0d0" }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { text: "Status:"; font.pixelSize: 18; color: "#666666" }
                Text {
                    text: dataTimer.running ? "● RUNNING" : "○ STOPPED"
                    font.pixelSize: 18; font.bold: true
                    color: dataTimer.running ? "#2e7d32" : "#c62828"
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { text: "Time:"; font.pixelSize: 18; color: "#666666" }
                Text { id: timeLabel; text: "0.0 s"; font.pixelSize: 18; font.bold: true; color: "#3a3a5c" }
            }

            Rectangle { Layout.fillWidth: true; height: 2; color: "#d0d0d0" }

            Text { text: "Input Value"; font.pixelSize: 16; color: "#666666" }

            Text {
                text: inputValue.toFixed(1)
                font.pixelSize: 60; font.bold: true; color: "#3a3a5c"
                Layout.alignment: Qt.AlignHCenter
            }

            Slider {
                id: valueSlider
                Layout.fillWidth: true
                from: -100; to: 100; value: 0; stepSize: 0.1
                onValueChanged: root.inputValue = value
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                TextField {
                    id: valueInput
                    Layout.fillWidth: true
                    placeholderText: "값 입력 (-100 ~ 100)"
                    font.pixelSize: 16
                    validator: DoubleValidator { bottom: -100; top: 100 }
                    onAccepted: {
                        var val = parseFloat(text)
                        if (!isNaN(val)) { root.inputValue = val; valueSlider.value = val }
                    }
                }

                Button {
                    text: "적용"; font.pixelSize: 16
                    onClicked: {
                        var val = parseFloat(valueInput.text)
                        if (!isNaN(val)) { root.inputValue = val; valueSlider.value = val }
                    }
                }
            }

            Text { text: "Presets"; font.pixelSize: 16; color: "#666666"; Layout.topMargin: 10 }

            GridLayout {
                Layout.fillWidth: true; columns: 3; rowSpacing: 10; columnSpacing: 10
                Button { text: "-100"; onClicked: { root.inputValue = -100; valueSlider.value = -100 } }
                Button { text: "-50";  onClicked: { root.inputValue = -50;  valueSlider.value = -50 } }
                Button { text: "-10";  onClicked: { root.inputValue = -10;  valueSlider.value = -10 } }
                Button { text: "0";    onClicked: { root.inputValue = 0;    valueSlider.value = 0 } }
                Button { text: "10";   onClicked: { root.inputValue = 10;   valueSlider.value = 10 } }
                Button { text: "50";   onClicked: { root.inputValue = 50;   valueSlider.value = 50 } }
                Button { text: "100";  onClicked: { root.inputValue = 100;  valueSlider.value = 100 } }
            }

            Rectangle { Layout.fillWidth: true; height: 2; color: "#d0d0d0" }

            Text { text: "Y-Axis Range"; font.pixelSize: 16; color: "#666666" }

            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Text { text: "Min:"; font.pixelSize: 14 }
                SpinBox { id: yMinSpin; from: -1000; to: 0; value: -100; editable: true; onValueChanged: axisY.min = value }
                Text { text: "Max:"; font.pixelSize: 14 }
                SpinBox { id: yMaxSpin; from: 0; to: 1000; value: 100; editable: true; onValueChanged: axisY.max = value }
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true; spacing: 15
                Button {
                    Layout.fillWidth: true; text: dataTimer.running ? "■ Stop" : "▶ Start"
                    font.pixelSize: 20; font.bold: true
                    onClicked: dataTimer.running = !dataTimer.running
                }
                Button {
                    Layout.fillWidth: true; text: "↺ Reset"; font.pixelSize: 20; font.bold: true
                    onClicked: {
                        dataTimer.running = false; lineSeries.clear(); timeIndex = 0
                        inputValue = 0; valueSlider.value = 0
                        axisX.min = 0; axisX.max = 20; timeLabel.text = "0.0 s"
                    }
                }
            }
        }
    }
}
