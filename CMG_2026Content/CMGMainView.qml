import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCharts

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: "#e8e8e8"

    property real rollAngleValue: 0.0
    property real gimbalAngleValue: 0.0
    property real rollVelocityValue: 0.0
    property real gimbalVelocityValue: 0.0
    property real torqueValue: 0.0
    property int timeIndex: 0
    property bool isRunning: false
    property int maxPoints: 200

    property bool lampGimbalMotor: false
    property bool lampAngleSensor: false
    property bool lampWheelMotor: false
    property bool lampRPM1Sensor: false
    property bool lampRPM2Sensor: false
    property bool lampMainLoop: false
    property bool lampStable: false
    property bool lampStandard: false
    property bool lampPerformance: false

    // ── 앱 시작 시 자동 시리얼 연결 ──
    Component.onCompleted: {
        if (serialManager) {
            serialManager.refreshPorts()
            var ports = serialManager.availablePorts
            // 사용 가능한 포트가 있으면 첫 번째 포트로 자동 연결
            if (ports.length > 0) {
                portField.text = ports[ports.length - 1]  // 마지막 포트 (보통 가장 최근 연결된 장치)
            }
            console.log("Auto-connect:", portField.text, baudField.text)
            serialManager.connectPort(portField.text, Number(baudField.text))
        }
    }

    // ── serialManager 텔레메트리 수신 → 기존 프로퍼티 업데이트 ──
    Connections {
        target: serialManager ? serialManager : null
        function onTelemetryUpdated() {
            root.rollAngleValue = serialManager.roll
            root.gimbalAngleValue = serialManager.gimbalAngle
            root.rollVelocityValue = serialManager.gyroX
            root.gimbalVelocityValue = serialManager.gimbalVelocity
            root.torqueValue = (serialManager.wheel1Rpm / 1000.0) * serialManager.gimbalVelocity
            // comm_bits → 램프
            root.lampAngleSensor = (serialManager.commBits & 0x01) !== 0
            root.lampRPM1Sensor  = (serialManager.commBits & 0x02) !== 0
            root.lampRPM2Sensor  = (serialManager.commBits & 0x04) !== 0
            root.lampWheelMotor  = (serialManager.commBits & 0x08) !== 0
            root.lampGimbalMotor = (serialManager.commBits & 0x10) !== 0
            root.lampMainLoop    = (serialManager.commBits & 0x20) !== 0
        }
        // 연결/에러 로그 → 제목 바 날짜 위치에 임시 표시
        function onLogReceived(message) {
            dateTimeLabel.text = message
            console.log("SerialLog:", message)
        }
    }

    // ── RPM 명령 디바운스 (R 명령) ──
    Timer {
        id: rpmSendTimer; interval: 300
        onTriggered: {
            if (serialManager && serialManager.connected)
                serialManager.sendRPM(Number(rpmField.text))
        }
    }

    // ── PID 명령 디바운스 (K 명령) ──
    Timer {
        id: pidSendTimer; interval: 500
        onTriggered: {
            if (serialManager && serialManager.connected)
                serialManager.setBalancingPID(
                    Number(kpField.text), Number(kiField.text),
                    Number(kdField.text), Number(gainField.text))
        }
    }

    // Y축 자동 스케일: 값이 범위를 넘으면 여유(10%) 두고 확장
    function autoScaleY(axis, value) {
        var margin = Math.max(Math.abs(axis.max - axis.min) * 0.1, 0.1)
        if (value > axis.max) axis.max = value + margin
        if (value < axis.min) axis.min = value - margin
    }

    Timer {
        id: dataTimer
        interval: 100; running: root.isRunning; repeat: true
        onTriggered: {
            var t = timeIndex * 0.1
            rollAngleSeries.append(t, rollAngleValue)
            gimbalAngleSeries.append(t, gimbalAngleValue)
            rollVelocitySeries.append(t, rollVelocityValue)
            gimbalVelocitySeries.append(t, gimbalVelocityValue)
            torqueSeries.append(t, torqueValue)
            // Y축 자동 스케일
            autoScaleY(rollAngleAxisY, rollAngleValue)
            autoScaleY(gimbalAngleAxisY, gimbalAngleValue)
            autoScaleY(rollVelAxisY, rollVelocityValue)
            autoScaleY(gimbalVelAxisY, gimbalVelocityValue)
            autoScaleY(torqueAxisY, torqueValue)
            if (fileLogger) {
                fileLogger.appendData("RollAngle", t, rollAngleValue)
                fileLogger.appendData("GimbalAngle", t, gimbalAngleValue)
                fileLogger.appendData("RollVelocity", t, rollVelocityValue)
                fileLogger.appendData("GimbalVelocity", t, gimbalVelocityValue)
                fileLogger.appendData("Torque", t, torqueValue)
            }
            if (rollAngleSeries.count > maxPoints) {
                rollAngleSeries.remove(0); gimbalAngleSeries.remove(0)
                rollVelocitySeries.remove(0); gimbalVelocitySeries.remove(0)
                torqueSeries.remove(0)
            }
            if (t > 20) {
                var m = t - 20
                rollAngleAxisX.min=m; rollAngleAxisX.max=t; gimbalAngleAxisX.min=m; gimbalAngleAxisX.max=t
                rollVelAxisX.min=m; rollVelAxisX.max=t; gimbalVelAxisX.min=m; gimbalVelAxisX.max=t
                torqueAxisX.min=m; torqueAxisX.max=t
            }
            timeIndex++
            dateTimeLabel.text = Qt.formatDateTime(new Date(), "yyyy-MM-dd hh:mm:ss")
        }
    }

    onIsRunningChanged: {
        if (fileLogger) {
            if (isRunning) fileLogger.startSession(); else fileLogger.endSession()
        }
    }

    function resetAll() {
        isRunning = false; timeIndex = 0
        rollAngleSeries.clear(); gimbalAngleSeries.clear()
        rollVelocitySeries.clear(); gimbalVelocitySeries.clear(); torqueSeries.clear()
        rollAngleAxisX.min=0; rollAngleAxisX.max=20; gimbalAngleAxisX.min=0; gimbalAngleAxisX.max=20
        rollVelAxisX.min=0; rollVelAxisX.max=20; gimbalVelAxisX.min=0; gimbalVelAxisX.max=20
        torqueAxisX.min=0; torqueAxisX.max=20
        // Y축 초기 범위 복원
        rollAngleAxisY.min=-10; rollAngleAxisY.max=10
        gimbalAngleAxisY.min=-65; gimbalAngleAxisY.max=65
        rollVelAxisY.min=-1; rollVelAxisY.max=1
        gimbalVelAxisY.min=-1; gimbalVelAxisY.max=1
        torqueAxisY.min=-1; torqueAxisY.max=1
    }

    // ══════════════════════════════════════
    // 제목 바
    // ══════════════════════════════════════
    Rectangle {
        id: titleBar
        x: 8; y: 6; width: parent.width - 16; height: 40
        color: "#2c2c54"; radius: 3
        Text {
            id: dateTimeLabel
            anchors.left: parent.left; anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(new Date(), "yyyy-MM-dd hh:mm:ss")
            color: "#fff"; font.pixelSize: 22; font.italic: true
        }
        Text {
            anchors.centerIn: parent
            text: "Control Moment Gyroscope System  Ver 1.0"
            color: "#fff"; font.pixelSize: 24; font.bold: true
        }
    }

    // ══════════════════════════════════════
    // 좌측 (66%) - 그래프만
    // ══════════════════════════════════════
    GroupBox {
        id: leftArea
        x: 8; y: 52
        width: (parent.width - 24) * 0.66
        height: parent.height - 58
        title: "Realtime Graph"
        font.pixelSize: 20; font.bold: true

        GridLayout {
            anchors.fill: parent
            columns: 2; rows: 2; rowSpacing: 4; columnSpacing: 4

            ChartView {
                Layout.fillWidth: true; Layout.fillHeight: true
                antialiasing: true; backgroundColor: "#fff"; legend.visible: false
                title: "Roll Angle (θ)"; titleFont.pixelSize: 18
                ValuesAxis { id: rollAngleAxisX; min: 0; max: 20; titleText: "Time"; labelsFont.pixelSize: 14; gridLineColor: "#ddd" }
                ValuesAxis { id: rollAngleAxisY; min: -10; max: 10; tickCount: 11; titleText: "Roll Angle (θ)"; labelsFont.pixelSize: 14; gridLineColor: "#ddd" }
                LineSeries { id: rollAngleSeries; color: "#1a73e8"; width: 2; axisX: rollAngleAxisX; axisY: rollAngleAxisY }
            }
            ChartView {
                Layout.fillWidth: true; Layout.fillHeight: true
                antialiasing: true; backgroundColor: "#fff"; legend.visible: false
                title: "Gimbal Angle (θ)"; titleFont.pixelSize: 18
                ValuesAxis { id: gimbalAngleAxisX; min: 0; max: 20; titleText: "Time"; labelsFont.pixelSize: 14; gridLineColor: "#ddd" }
                ValuesAxis { id: gimbalAngleAxisY; min: -65; max: 65; tickCount: 9; titleText: "Gimbal Angle (θ)"; labelsFont.pixelSize: 14; gridLineColor: "#ddd" }
                LineSeries { id: gimbalAngleSeries; color: "#e8501a"; width: 2; axisX: gimbalAngleAxisX; axisY: gimbalAngleAxisY }
            }
            ChartView {
                Layout.fillWidth: true; Layout.fillHeight: true
                antialiasing: true; backgroundColor: "#fff"; legend.visible: false
                title: "Roll Velocity"; titleFont.pixelSize: 18
                ValuesAxis { id: rollVelAxisX; min: 0; max: 20; titleText: "Time"; labelsFont.pixelSize: 14; gridLineColor: "#ddd" }
                ValuesAxis { id: rollVelAxisY; min: -1; max: 1; tickCount: 11; titleText: "Roll Velocity"; labelsFont.pixelSize: 14; gridLineColor: "#ddd" }
                LineSeries { id: rollVelocitySeries; color: "#2e7d32"; width: 2; axisX: rollVelAxisX; axisY: rollVelAxisY }
            }
            ChartView {
                Layout.fillWidth: true; Layout.fillHeight: true
                antialiasing: true; backgroundColor: "#fff"; legend.visible: false
                title: "Gimbal Velocity"; titleFont.pixelSize: 18
                ValuesAxis { id: gimbalVelAxisX; min: 0; max: 20; titleText: "Time"; labelsFont.pixelSize: 14; gridLineColor: "#ddd" }
                ValuesAxis { id: gimbalVelAxisY; min: -1; max: 1; tickCount: 11; titleText: "Gimbal Velocity"; labelsFont.pixelSize: 14; gridLineColor: "#ddd" }
                LineSeries { id: gimbalVelocitySeries; color: "#6a1b9a"; width: 2; axisX: gimbalVelAxisX; axisY: gimbalVelAxisY }
            }
        }
    }

    // ══════════════════════════════════════
    // 우측 (34%) - 고정 좌표, Design Studio에서 드래그 가능
    // ══════════════════════════════════════
    // ── Main Loop ──
    GroupBox {
        id: mainLoopBox
        x: 1270; y: 52
        width: 640; height: 90
        title: "Main Loop"; font.pixelSize: 20; font.bold: true

        Row {
            anchors.fill: parent; spacing: 8
            Text { text: "Main_Loop"; font.pixelSize: 22; anchors.verticalCenter: parent.verticalCenter }
            // ── 포트 선택 (TextField + ▼ 드롭다운) ──
            Row {
                spacing: 0
                anchors.verticalCenter: parent.verticalCenter

                TextField {
                    id: portField
                    width: 100; height: 34; font.pixelSize: 20
                    text: "COM5"; readOnly: true
                    horizontalAlignment: Text.AlignHCenter
                }
                Rectangle {
                    width: 20; height: 34
                    color: portDropArea.pressed ? "#ccc" : "#e8e8e8"
                    border.color: "#aaa"; border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "▼"; font.pixelSize: 10
                    }

                    MouseArea {
                        id: portDropArea
                        anchors.fill: parent
                        onClicked: {
                            if (serialManager) {
                                serialManager.refreshPorts()
                            }
                            portPopup.open()
                        }
                    }
                }

                Popup {
                    id: portPopup
                    x: 0; y: 34
                    width: 120; padding: 2

                    Column {
                        width: parent.width
                        Repeater {
                            model: serialManager ? serialManager.availablePorts : ["COM5"]
                            delegate: Rectangle {
                                width: 116; height: 30
                                color: portItemArea.containsMouse ? "#d0d0ff" : "#fff"
                                border.color: "#ddd"; border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData; font.pixelSize: 18
                                }

                                MouseArea {
                                    id: portItemArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        portField.text = modelData
                                        portPopup.close()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Rectangle { width: 26; height: 26; radius: 3; border.color: "#333"; border.width: 1; color: root.lampMainLoop ? "#7fff00" : "#4a6741"; anchors.verticalCenter: parent.verticalCenter }
            Text { text: "Baud Rate"; font.pixelSize: 22; anchors.verticalCenter: parent.verticalCenter }
            // ── 보드레이트 선택 (TextField + ▼ 드롭다운) ──
            Row {
                spacing: 0
                anchors.verticalCenter: parent.verticalCenter

                TextField {
                    id: baudField
                    width: 100; height: 34; font.pixelSize: 20
                    text: "115200"; readOnly: true
                    horizontalAlignment: Text.AlignHCenter
                }
                Rectangle {
                    width: 20; height: 34
                    color: baudDropArea.pressed ? "#ccc" : "#e8e8e8"
                    border.color: "#aaa"; border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "▼"; font.pixelSize: 10
                    }

                    MouseArea {
                        id: baudDropArea
                        anchors.fill: parent
                        onClicked: baudPopup.open()
                    }
                }

                Popup {
                    id: baudPopup
                    x: 0; y: 34
                    width: 120; padding: 2

                    Column {
                        width: parent.width
                        Repeater {
                            model: ["9600", "19200", "38400", "57600", "115200"]
                            delegate: Rectangle {
                                width: 116; height: 30
                                color: baudItemArea.containsMouse ? "#d0d0ff" : "#fff"
                                border.color: "#ddd"; border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData; font.pixelSize: 18
                                }

                                MouseArea {
                                    id: baudItemArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        baudField.text = modelData
                                        baudPopup.close()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Realtime Sensor Data ──
    GroupBox {
        id: sensorBox
        x: 1270; y: 148
        width: 640; height: 122
        title: "Realtime Sensor Data"; font.pixelSize: 20; font.bold: true

        Grid {
            anchors.fill: parent; columns: 4; rowSpacing: 10; columnSpacing: 15
            Text { text: "Roll Angle"; font.pixelSize: 22; width: 130 }
            Text { text: rollAngleValue.toFixed(1) + " °"; font.pixelSize: 22; font.bold: true; width: 100; horizontalAlignment: Text.AlignRight }
            Text { text: "Wheel RPM1"; font.pixelSize: 22; width: 140 }
            Text { text: (serialManager ? serialManager.wheel1Rpm : 0) + " rpm"; font.pixelSize: 22; font.bold: true; width: 120; horizontalAlignment: Text.AlignRight }
            Text { text: "Gimbal Angle"; font.pixelSize: 22; width: 130 }
            Text { text: gimbalAngleValue.toFixed(1) + " °"; font.pixelSize: 22; font.bold: true; width: 100; horizontalAlignment: Text.AlignRight }
            Text { text: "Wheel RPM2"; font.pixelSize: 22; width: 140 }
            Text { text: (serialManager ? serialManager.wheel2Rpm : 0) + " rpm"; font.pixelSize: 22; font.bold: true; width: 120; horizontalAlignment: Text.AlignRight }
        }
    }

    // ── Control System ──
    GroupBox {
        id: controlBox
        x: 1270; y: 276
        width: 640; height: 148
        title: "Control System"; font.pixelSize: 20; font.bold: true

        Column {
            anchors.fill: parent; spacing: 10
            Row {
                id: controlRow1
                spacing: 10
                Text { text: "Setting Wheel RPM"; font.pixelSize: 22; anchors.verticalCenter: parent.verticalCenter }
                Row {
                    spacing: 0
                    anchors.verticalCenter: parent.verticalCenter
                    TextField { id: rpmField; width: 90; height: 40; text: "0"; font.pixelSize: 22; horizontalAlignment: Text.AlignHCenter; validator: IntValidator { bottom: 0; top: 10000 }
                        onAccepted: rpmSendTimer.restart()
                    }
                    Column {
                        spacing: 0
                        Rectangle {
                            width: 20; height: 20; color: rpmUp.pressed ? "#ccc" : "#e8e8e8"; border.color: "#aaa"; border.width: 1
                            Text { anchors.centerIn: parent; text: "▲"; font.pixelSize: 7 }
                            MouseArea { id: rpmUp; anchors.fill: parent; onClicked: { rpmField.text = String(Math.min(10000, Number(rpmField.text) + 100)); rpmSendTimer.restart() } }
                        }
                        Rectangle {
                            width: 20; height: 20; color: rpmDn.pressed ? "#ccc" : "#e8e8e8"; border.color: "#aaa"; border.width: 1
                            Text { anchors.centerIn: parent; text: "▼"; font.pixelSize: 7 }
                            MouseArea { id: rpmDn; anchors.fill: parent; onClicked: { rpmField.text = String(Math.max(0, Number(rpmField.text) - 100)); rpmSendTimer.restart() } }
                        }
                    }
                }
                Item { width: 15; height: 1 }
                Text { text: "Control_Factor"; font.pixelSize: 22; anchors.verticalCenter: parent.verticalCenter }
                TextField { width: 75; height: 40; text: "2.5"; font.pixelSize: 22; horizontalAlignment: Text.AlignHCenter }
            }
            Item {
                width: controlRow1.implicitWidth; height: 45
                Text { id: dataFileLabel; text: "Data File"; font.pixelSize: 22; anchors.verticalCenter: parent.verticalCenter }
                Rectangle {
                    id: startBtn
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 130; height: 40; radius: 0
                    color: startBtnArea.pressed ? "#ccc" : "#e8e8e8"
                    border.color: "#aaa"; border.width: 1
                    Text { anchors.centerIn: parent; text: root.isRunning ? "Stop Test" : "Start Test"; font.pixelSize: 22; font.bold: true }
                    MouseArea {
                        id: startBtnArea; anchors.fill: parent
                        onClicked: {
                            if (!root.isRunning) {
                                // Start: 미연결 시 자동 연결 → RPM 설정 → 밸런싱 시작 (B1)
                                if (serialManager) {
                                    if (!serialManager.connected)
                                        serialManager.connectPort(portField.text, Number(baudField.text))
                                    serialManager.sendRPM(Number(rpmField.text))
                                    serialManager.setBalancingPID(Number(kpField.text), Number(kiField.text), Number(kdField.text), Number(gainField.text))
                                    serialManager.startBalancing()
                                }
                            } else {
                                // Stop: 밸런싱 정지 (B0)
                                if (serialManager && serialManager.connected)
                                    serialManager.stopBalancing()
                            }
                            root.isRunning = !root.isRunning
                        }
                    }
                }
                Rectangle {
                    id: browseBtn
                    anchors.right: startBtn.left; anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40; height: 40; radius: 0
                    color: browseBtnArea.pressed ? "#ccc" : "#e8e8e8"
                    border.color: "#aaa"; border.width: 1
                    Text { anchors.centerIn: parent; text: "..."; font.pixelSize: 20 }
                    MouseArea { id: browseBtnArea; anchors.fill: parent }
                }
                TextField {
                    anchors.left: dataFileLabel.right; anchors.leftMargin: 10
                    anchors.right: browseBtn.left; anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    height: 40; font.pixelSize: 22; horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    // ── Performance Metrics ──
    GroupBox {
        id: perfBox
        x: 1270; y: 430
        width: 640; height: 141
        title: "Performance Metrics"; font.pixelSize: 20; font.bold: true

        Column {
            anchors.fill: parent; spacing: 8
            Row {
                anchors.horizontalCenter: parent.horizontalCenter; spacing: 15
                Text { text: "Kp"; font.pixelSize: 26; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                Row {
                    spacing: 0
                    TextField { id: kpField; width: 75; height: 40; text: "50"; font.pixelSize: 24; horizontalAlignment: Text.AlignHCenter }
                    Column {
                        spacing: 0
                        Rectangle {
                            width: 20; height: 20; color: kpUp.pressed ? "#ccc" : "#e8e8e8"; border.color: "#aaa"; border.width: 1
                            Text { anchors.centerIn: parent; text: "▲"; font.pixelSize: 7 }
                            MouseArea { id: kpUp; anchors.fill: parent; onClicked: { kpField.text = String(Number(kpField.text) + 1); pidSendTimer.restart() } }
                        }
                        Rectangle {
                            width: 20; height: 20; color: kpDn.pressed ? "#ccc" : "#e8e8e8"; border.color: "#aaa"; border.width: 1
                            Text { anchors.centerIn: parent; text: "▼"; font.pixelSize: 7 }
                            MouseArea { id: kpDn; anchors.fill: parent; onClicked: { kpField.text = String(Math.max(0, Number(kpField.text) - 1)); pidSendTimer.restart() } }
                        }
                    }
                }
                Text { text: "Ki"; font.pixelSize: 26; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                Row {
                    spacing: 0
                    TextField { id: kiField; width: 75; height: 40; text: "0.03"; font.pixelSize: 24; horizontalAlignment: Text.AlignHCenter }
                    Column {
                        spacing: 0
                        Rectangle {
                            width: 20; height: 20; color: kiUp.pressed ? "#ccc" : "#e8e8e8"; border.color: "#aaa"; border.width: 1
                            Text { anchors.centerIn: parent; text: "▲"; font.pixelSize: 7 }
                            MouseArea { id: kiUp; anchors.fill: parent; onClicked: { kiField.text = String((Number(kiField.text) + 0.01).toFixed(2)); pidSendTimer.restart() } }
                        }
                        Rectangle {
                            width: 20; height: 20; color: kiDn.pressed ? "#ccc" : "#e8e8e8"; border.color: "#aaa"; border.width: 1
                            Text { anchors.centerIn: parent; text: "▼"; font.pixelSize: 7 }
                            MouseArea { id: kiDn; anchors.fill: parent; onClicked: { kiField.text = String(Math.max(0, (Number(kiField.text) - 0.01)).toFixed(2)); pidSendTimer.restart() } }
                        }
                    }
                }
                Text { text: "Kd"; font.pixelSize: 26; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                Row {
                    spacing: 0
                    TextField { id: kdField; width: 75; height: 40; text: "20"; font.pixelSize: 24; horizontalAlignment: Text.AlignHCenter }
                    Column {
                        spacing: 0
                        Rectangle {
                            width: 20; height: 20; color: kdUp.pressed ? "#ccc" : "#e8e8e8"; border.color: "#aaa"; border.width: 1
                            Text { anchors.centerIn: parent; text: "▲"; font.pixelSize: 7 }
                            MouseArea { id: kdUp; anchors.fill: parent; onClicked: { kdField.text = String(Number(kdField.text) + 1); pidSendTimer.restart() } }
                        }
                        Rectangle {
                            width: 20; height: 20; color: kdDn.pressed ? "#ccc" : "#e8e8e8"; border.color: "#aaa"; border.width: 1
                            Text { anchors.centerIn: parent; text: "▼"; font.pixelSize: 7 }
                            MouseArea { id: kdDn; anchors.fill: parent; onClicked: { kdField.text = String(Math.max(0, Number(kdField.text) - 1)); pidSendTimer.restart() } }
                        }
                    }
                }
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter; spacing: 8
                Text { text: "Gimbal Reset Gain"; font.pixelSize: 24; anchors.verticalCenter: parent.verticalCenter }
                Row {
                    spacing: 0
                    TextField { id: gainField; width: 75; height: 40; text: "0.03"; font.pixelSize: 24; horizontalAlignment: Text.AlignHCenter }
                    Column {
                        spacing: 0
                        Rectangle {
                            width: 20; height: 20; color: gainUp.pressed ? "#ccc" : "#e8e8e8"; border.color: "#aaa"; border.width: 1
                            Text { anchors.centerIn: parent; text: "▲"; font.pixelSize: 7 }
                            MouseArea { id: gainUp; anchors.fill: parent; onClicked: { gainField.text = String((Number(gainField.text) + 0.01).toFixed(2)); pidSendTimer.restart() } }
                        }
                        Rectangle {
                            width: 20; height: 20; color: gainDn.pressed ? "#ccc" : "#e8e8e8"; border.color: "#aaa"; border.width: 1
                            Text { anchors.centerIn: parent; text: "▼"; font.pixelSize: 7 }
                            MouseArea { id: gainDn; anchors.fill: parent; onClicked: { gainField.text = String(Math.max(0, (Number(gainField.text) - 0.01)).toFixed(2)); pidSendTimer.restart() } }
                        }
                    }
                }
            }
        }
    }

    // ── Torque Trend ──
    GroupBox {
        id: torqueBox
        x: 1270; y: 577
        width: 640; height: 497
        title: "Torque Trend"; font.pixelSize: 20; font.bold: true

        Item {
            anchors.fill: parent
            Row {
                anchors.top: parent.top; anchors.right: parent.right; spacing: 8; z: 1
                Text { text: "Torque_Nm"; font.pixelSize: 24; font.bold: true }
                Text { text: torqueValue.toFixed(2) + " Nm"; font.pixelSize: 26; font.bold: true; color: "#c62828" }
            }
            ChartView {
                anchors.fill: parent; anchors.topMargin: 30
                antialiasing: true; backgroundColor: "#fff"; legend.visible: false
                ValuesAxis { id: torqueAxisX; min: 0; max: 20; titleText: "Time"; labelsFont.pixelSize: 14; gridLineColor: "#ddd" }
                ValuesAxis { id: torqueAxisY; min: -1; max: 1; tickCount: 11; titleText: "Torque (Nm)"; labelsFont.pixelSize: 14; gridLineColor: "#ddd" }
                LineSeries { id: torqueSeries; color: "#c62828"; width: 2; axisX: torqueAxisX; axisY: torqueAxisY }
            }
        }
    }
}
