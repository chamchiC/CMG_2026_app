import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCharts
import QtQuick.Dialogs

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: colBg

    // ── 카본/메탈 테마 팔레트 ──
    readonly property color colBg:         "#1c1c1c"
    readonly property color colPanel:      "#2a2a2a"
    readonly property color colTitleBar:   "#333333"
    readonly property color colText:       "#e8e8e8"
    readonly property color colAccent:     "#f0a500"
    readonly property color colLabel:      "#c8c8c8"
    readonly property color colInputBg:    "#1a1a1a"
    readonly property color colInputBorder:"#555555"
    readonly property color colBtn:        "#3a3a3a"
    readonly property color colBtnHover:   "#505050"
    readonly property color colChartBg:    "#141414"
    readonly property color colGrid:       "#3a3a3a"
    readonly property color colLampOn:     "#00ff88"
    readonly property color colLampOff:    "#2a3a2e"

    // ── 폰트 ──
    readonly property string monoFont: "Consolas"

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
            if (ports.length > 0) {
                portField.text = ports[ports.length - 1]
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
            root.lampAngleSensor = (serialManager.commBits & 0x01) !== 0
            root.lampRPM1Sensor  = (serialManager.commBits & 0x02) !== 0
            root.lampRPM2Sensor  = (serialManager.commBits & 0x04) !== 0
            root.lampWheelMotor  = (serialManager.commBits & 0x08) !== 0
            root.lampGimbalMotor = (serialManager.commBits & 0x10) !== 0
            root.lampMainLoop    = (serialManager.commBits & 0x20) !== 0
            root.lampStable      = Math.abs(serialManager.roll) < 2.0
            root.lampStandard    = serialManager.balancing
            root.lampPerformance = serialManager.wheelState === 1
        }
        function onLogReceived(message) {
            var formatted = formatLog(message)
            console.log("SerialLog:", formatted)
            classifyAndAppend(message)
        }
    }

    // ── RPM 명령 디바운스 (R 명령) ──
    Timer {
        id: rpmSendTimer; interval: 300
        onTriggered: {
            if (serialManager && serialManager.connected) {
                var rpm = Number(rpmField.text)
                serialManager.sendRPM(rpm)
                appendToLog(rpmLogModel, "TX: R" + rpm)
            }
        }
    }

    // ── PID 명령 디바운스 (K 명령) ──
    Timer {
        id: pidSendTimer; interval: 500
        onTriggered: {
            if (serialManager && serialManager.connected) {
                var kp = Number(kpField.text), ki = Number(kiField.text)
                var kd = Number(kdField.text), g = Number(gainField.text)
                serialManager.setBalancingPID(kp, ki, kd, g)
                appendToLog(pidLogModel, "TX: K" + kp + "," + ki + "," + kd + "," + g)
            }
        }
    }

    // Y축 자동 스케일
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
            autoScaleY(rollAngleAxisY, rollAngleValue)
            autoScaleY(gimbalAngleAxisY, gimbalAngleValue)
            autoScaleY(rollVelAxisY, rollVelocityValue)
            autoScaleY(gimbalVelAxisY, gimbalVelocityValue)
            autoScaleY(torqueAxisY, torqueValue)
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
        if (serialManager) {
            if (isRunning) serialManager.startRecording(dataFileField.text)
            else serialManager.stopRecording()
        }
    }

    function resetAll() {
        isRunning = false; timeIndex = 0
        rollAngleSeries.clear(); gimbalAngleSeries.clear()
        rollVelocitySeries.clear(); gimbalVelocitySeries.clear(); torqueSeries.clear()
        rollAngleAxisX.min=0; rollAngleAxisX.max=20; gimbalAngleAxisX.min=0; gimbalAngleAxisX.max=20
        rollVelAxisX.min=0; rollVelAxisX.max=20; gimbalVelAxisX.min=0; gimbalVelAxisX.max=20
        torqueAxisX.min=0; torqueAxisX.max=20
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
        x: 8; y: 6; width: parent.width - 16; height: 44
        color: colTitleBar; radius: 0
        border.color: colInputBorder; border.width: 1
        Text {
            id: dateTimeLabel
            anchors.left: parent.left; anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(new Date(), "yyyy-MM-dd hh:mm:ss")
            color: colLabel; font.pixelSize: 16; font.family: monoFont
        }
        // ── 연결 상태 표시 ──
        Text {
            id: connStatusLabel
            anchors.left: dateTimeLabel.right; anchors.leftMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            text: serialManager ? serialManager.connectionStatus : "---"
            font.pixelSize: 18; font.family: monoFont; font.bold: true
            color: {
                if (!serialManager) return colLabel
                var s = serialManager.connectionStatus
                if (s.indexOf("Connected:") === 0) return colLampOn
                if (s.indexOf("Connecting") === 0) return colAccent
                if (s.indexOf("No data") === 0) return "#e84040"
                return colLabel
            }
        }
        Text {
            anchors.centerIn: parent
            text: "CONTROL MOMENT GYROSCOPE SYSTEM  v1.0"
            color: colAccent; font.pixelSize: 22; font.bold: true; font.family: monoFont; font.letterSpacing: 2
        }
        // ── 설정 버튼 ──
        Rectangle {
            anchors.right: parent.right; anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 32; height: 32; radius: 0
            color: settingsBtnArea.containsMouse ? colBtnHover : "transparent"
            border.color: settingsBtnArea.containsMouse ? colInputBorder : "transparent"; border.width: 1
            Text {
                anchors.centerIn: parent
                text: "\u2699"; font.pixelSize: 20; color: colText
            }
            MouseArea {
                id: settingsBtnArea; anchors.fill: parent
                hoverEnabled: true
                onClicked: settingsPopup.open()
            }
        }
    }

    // ── 설정 팝업 (4칼럼 로그) ──
    Popup {
        id: settingsPopup
        x: (root.width - 1200) / 2; y: 55
        width: 1200; padding: 12
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onOpened: {
            Qt.callLater(function() {
                rpmLogView.positionViewAtEnd()
                pidLogView.positionViewAtEnd()
                rxLogView.positionViewAtEnd()
                pktLogView.positionViewAtEnd()
            })
        }
        background: Rectangle { color: colPanel; radius: 0; border.color: colAccent; border.width: 1 }
        Column {
            spacing: 10; width: parent.width
            // ── 헤더 ──
            Row {
                spacing: 0; width: parent.width
                Text { width: parent.width / 4; text: "[ RPM TX ]"; font.pixelSize: 16; font.bold: true; font.family: monoFont; color: colAccent; horizontalAlignment: Text.AlignHCenter }
                Text { width: parent.width / 4; text: "[ PID TX ]"; font.pixelSize: 16; font.bold: true; font.family: monoFont; color: colAccent; horizontalAlignment: Text.AlignHCenter }
                Text { width: parent.width / 4; text: "[ RX ]"; font.pixelSize: 16; font.bold: true; font.family: monoFont; color: colAccent; horizontalAlignment: Text.AlignHCenter }
                Text { width: parent.width / 4; text: "[ PKT ]"; font.pixelSize: 16; font.bold: true; font.family: monoFont; color: colAccent; horizontalAlignment: Text.AlignHCenter }
            }
            // ── 4칼럼 로그 영역 ──
            Row {
                spacing: 6; width: parent.width
                // RPM TX
                Rectangle {
                    width: (parent.width - 18) / 4; height: 400; color: colInputBg; radius: 0; border.color: colInputBorder; border.width: 1
                    ListView {
                        id: rpmLogView; anchors.fill: parent; anchors.margins: 6; clip: true; model: rpmLogModel
                        delegate: Text { width: rpmLogView.width; text: modelData; color: "#f0a500"; font.pixelSize: 11; font.family: monoFont; wrapMode: Text.Wrap }
                    }
                }
                // PID TX
                Rectangle {
                    width: (parent.width - 18) / 4; height: 400; color: colInputBg; radius: 0; border.color: colInputBorder; border.width: 1
                    ListView {
                        id: pidLogView; anchors.fill: parent; anchors.margins: 6; clip: true; model: pidLogModel
                        delegate: Text { width: pidLogView.width; text: modelData; color: "#80cbc4"; font.pixelSize: 11; font.family: monoFont; wrapMode: Text.Wrap }
                    }
                }
                // RX
                Rectangle {
                    width: (parent.width - 18) / 4; height: 400; color: colInputBg; radius: 0; border.color: colInputBorder; border.width: 1
                    ListView {
                        id: rxLogView; anchors.fill: parent; anchors.margins: 6; clip: true; model: rxLogModel
                        delegate: Text { width: rxLogView.width; text: modelData; color: colText; font.pixelSize: 11; font.family: monoFont; wrapMode: Text.Wrap }
                    }
                }
                // PKT
                Rectangle {
                    width: (parent.width - 18) / 4; height: 400; color: colInputBg; radius: 0; border.color: colInputBorder; border.width: 1
                    ListView {
                        id: pktLogView; anchors.fill: parent; anchors.margins: 6; clip: true; model: pktLogModel
                        delegate: Text { width: pktLogView.width; text: modelData; color: "#c0c0c0"; font.pixelSize: 11; font.family: monoFont; wrapMode: Text.Wrap }
                    }
                }
            }
            // ── 닫기 버튼 ──
            Rectangle {
                width: 90; height: 30; radius: 0; color: closeBtnArea.pressed ? colBtnHover : colBtn
                border.color: colInputBorder; border.width: 1
                anchors.horizontalCenter: parent.horizontalCenter
                Text { anchors.centerIn: parent; text: "CLOSE"; color: colText; font.pixelSize: 13; font.family: monoFont; font.bold: true }
                MouseArea { id: closeBtnArea; anchors.fill: parent; onClicked: settingsPopup.close() }
            }
        }
    }

    // ── 로그 모델 (4개) ──
    ListModel { id: rpmLogModel }
    ListModel { id: pidLogModel }
    ListModel { id: rxLogModel }
    ListModel { id: pktLogModel }

    function appendToLog(model, msg) {
        model.append({"modelData": msg})
        if (model.count > 100) model.remove(0)
        if (settingsPopup.opened) {
            if (model === rpmLogModel) Qt.callLater(rpmLogView.positionViewAtEnd)
            else if (model === pidLogModel) Qt.callLater(pidLogView.positionViewAtEnd)
            else if (model === rxLogModel) Qt.callLater(rxLogView.positionViewAtEnd)
            else if (model === pktLogModel) Qt.callLater(pktLogView.positionViewAtEnd)
        }
    }
    function classifyAndAppend(msg) {
        var formatted = formatLog(msg)
        // PKT 로그 → PKT 칼럼
        if (msg.indexOf("PKT #") === 0) {
            appendToLog(pktLogModel, msg); return
        }
        // JSON에서 detail 필드로 분류
        var idx = msg.indexOf('{')
        if (idx >= 0) {
            try {
                var obj = JSON.parse(msg.substring(idx))
                var d = (obj.detail || "").toUpperCase()
                if (d.indexOf("CMD:R") >= 0 || d.indexOf("RPM") >= 0) {
                    appendToLog(rpmLogModel, formatted); return
                }
                if (d.indexOf("CMD:K") >= 0 || d.indexOf("CMD:B") >= 0 || d.indexOf("CMD:W") >= 0
                    || d.indexOf("BALANCING") >= 0 || d.indexOf("PID") >= 0) {
                    appendToLog(pidLogModel, formatted); return
                }
            } catch(e) {}
        }
        // 나머지 전부 RX (RX bytes, CHECKSUM FAIL, Buffer overflow, ASCII 등)
        appendToLog(rxLogModel, formatted)
    }
    function formatLog(msg) {
        // JSON 메시지 감지 및 포맷
        var idx = msg.indexOf('{')
        if (idx < 0) return msg
        try {
            var prefix = msg.substring(0, idx).trim()
            var obj = JSON.parse(msg.substring(idx))
            var t = obj.t !== undefined ? obj.t : "?"
            var ev = obj.event || "?"
            var detail = obj.detail || ""
            var lines = "[" + t + "] " + ev + ": " + detail
            // 주요 상태 표시
            var state = []
            if (obj.wheelState !== undefined) state.push("wheel=" + obj.wheelState)
            if (obj.balancing !== undefined)  state.push("bal=" + (obj.balancing ? "ON" : "OFF"))
            if (obj.targetRPM !== undefined)  state.push("RPM=" + obj.targetRPM)
            if (obj.targetGimbal !== undefined) state.push("gimbal=" + obj.targetGimbal)
            if (state.length > 0) lines += "\n  " + state.join("  ")
            // 통신 상태 (변경 이벤트일 때만)
            if (obj.event === "comm" || obj.event === "init") {
                var c = obj.comm
                if (c) {
                    var sensors = []
                    if (c.angleSensor) sensors.push("angle"); else sensors.push("!angle")
                    if (c.rpmSensor1) sensors.push("rpm1"); else sensors.push("!rpm1")
                    if (c.rpmSensor2) sensors.push("rpm2"); else sensors.push("!rpm2")
                    if (c.wheelMotor) sensors.push("wheel"); else sensors.push("!wheel")
                    if (c.gimbalMotor) sensors.push("gimbal"); else sensors.push("!gimbal")
                    if (c.mainLoop) sensors.push("main"); else sensors.push("!main")
                    lines += "\n  comm: " + sensors.join(" ")
                }
            }
            return prefix ? (prefix + "\n" + lines) : lines
        } catch(e) {
            return msg  // JSON 파싱 실패 → 원본 그대로
        }
    }

    // ══════════════════════════════════════
    // 좌측 (66%) - 그래프
    // ══════════════════════════════════════
    GroupBox {
        id: leftArea
        x: 8; y: 56
        width: (parent.width - 24) * 0.66
        height: parent.height - 62
        label: Text { text: "[ REALTIME GRAPH ]"; font.pixelSize: 22; font.bold: true; font.family: monoFont; color: colAccent }
        background: Rectangle { color: colPanel; radius: 0; border.color: colInputBorder; border.width: 1 }

        GridLayout {
            anchors.fill: parent
            columns: 2; rows: 2; rowSpacing: 4; columnSpacing: 4

            ChartView {
                Layout.fillWidth: true; Layout.fillHeight: true
                antialiasing: true; backgroundColor: colChartBg; legend.visible: false
                title: "ROLL ANGLE"; titleFont.pixelSize: 14; titleColor: colLabel; titleFont.family: monoFont
                plotAreaColor: colChartBg
                ValuesAxis { id: rollAngleAxisX; min: 0; max: 20; titleText: "Time"; labelsFont.pixelSize: 11; labelsFont.family: monoFont; gridLineColor: colGrid; labelsColor: colLabel; titleBrush: colLabel }
                ValuesAxis { id: rollAngleAxisY; min: -10; max: 10; tickCount: 11; titleText: "Roll (deg)"; labelsFont.pixelSize: 11; labelsFont.family: monoFont; gridLineColor: colGrid; labelsColor: colLabel; titleBrush: colLabel }
                LineSeries { id: rollAngleSeries; color: "#f0a500"; width: 2; axisX: rollAngleAxisX; axisY: rollAngleAxisY }
            }
            ChartView {
                Layout.fillWidth: true; Layout.fillHeight: true
                antialiasing: true; backgroundColor: colChartBg; legend.visible: false
                title: "GIMBAL ANGLE"; titleFont.pixelSize: 14; titleColor: colLabel; titleFont.family: monoFont
                plotAreaColor: colChartBg
                ValuesAxis { id: gimbalAngleAxisX; min: 0; max: 20; titleText: "Time"; labelsFont.pixelSize: 11; labelsFont.family: monoFont; gridLineColor: colGrid; labelsColor: colLabel; titleBrush: colLabel }
                ValuesAxis { id: gimbalAngleAxisY; min: -65; max: 65; tickCount: 9; titleText: "Gimbal (deg)"; labelsFont.pixelSize: 11; labelsFont.family: monoFont; gridLineColor: colGrid; labelsColor: colLabel; titleBrush: colLabel }
                LineSeries { id: gimbalAngleSeries; color: "#e8e8e8"; width: 2; axisX: gimbalAngleAxisX; axisY: gimbalAngleAxisY }
            }
            ChartView {
                Layout.fillWidth: true; Layout.fillHeight: true
                antialiasing: true; backgroundColor: colChartBg; legend.visible: false
                title: "ROLL VELOCITY"; titleFont.pixelSize: 14; titleColor: colLabel; titleFont.family: monoFont
                plotAreaColor: colChartBg
                ValuesAxis { id: rollVelAxisX; min: 0; max: 20; titleText: "Time"; labelsFont.pixelSize: 11; labelsFont.family: monoFont; gridLineColor: colGrid; labelsColor: colLabel; titleBrush: colLabel }
                ValuesAxis { id: rollVelAxisY; min: -1; max: 1; tickCount: 11; titleText: "Roll Vel"; labelsFont.pixelSize: 11; labelsFont.family: monoFont; gridLineColor: colGrid; labelsColor: colLabel; titleBrush: colLabel }
                LineSeries { id: rollVelocitySeries; color: "#c0c0c0"; width: 2; axisX: rollVelAxisX; axisY: rollVelAxisY }
            }
            ChartView {
                Layout.fillWidth: true; Layout.fillHeight: true
                antialiasing: true; backgroundColor: colChartBg; legend.visible: false
                title: "GIMBAL VELOCITY"; titleFont.pixelSize: 14; titleColor: colLabel; titleFont.family: monoFont
                plotAreaColor: colChartBg
                ValuesAxis { id: gimbalVelAxisX; min: 0; max: 20; titleText: "Time"; labelsFont.pixelSize: 11; labelsFont.family: monoFont; gridLineColor: colGrid; labelsColor: colLabel; titleBrush: colLabel }
                ValuesAxis { id: gimbalVelAxisY; min: -1; max: 1; tickCount: 11; titleText: "Gimbal Vel"; labelsFont.pixelSize: 11; labelsFont.family: monoFont; gridLineColor: colGrid; labelsColor: colLabel; titleBrush: colLabel }
                LineSeries { id: gimbalVelocitySeries; color: "#d4770b"; width: 2; axisX: gimbalVelAxisX; axisY: gimbalVelAxisY }
            }
        }
    }

    // ══════════════════════════════════════
    // 우측 (34%) - 패널들
    // ══════════════════════════════════════

    // ── Main Loop ──
    GroupBox {
        id: mainLoopBox
        x: 1270; y: 56
        width: 640; height: 90
        label: Text { text: "[ MAIN LOOP ]"; font.pixelSize: 22; font.bold: true; font.family: monoFont; color: colAccent }
        background: Rectangle { color: colPanel; radius: 0; border.color: colInputBorder; border.width: 1 }

        Row {
            anchors.fill: parent; spacing: 8
            Text { text: "MAIN_LOOP"; font.pixelSize: 20; font.family: monoFont; color: colLabel; anchors.verticalCenter: parent.verticalCenter }
            Row {
                spacing: 0; anchors.verticalCenter: parent.verticalCenter
                TextField {
                    id: portField; width: 100; height: 34; font.pixelSize: 16; font.family: monoFont
                    text: "COM5"; readOnly: true; horizontalAlignment: Text.AlignHCenter
                    color: colAccent
                    background: Rectangle { color: colInputBg; radius: 0; border.color: colInputBorder; border.width: 1 }
                }
                Rectangle {
                    width: 22; height: 34; radius: 0; color: portDropArea.pressed ? colBtnHover : colBtn
                    border.color: colInputBorder; border.width: 1
                    Text { anchors.centerIn: parent; text: "\u25BC"; font.pixelSize: 10; color: colText }
                    MouseArea {
                        id: portDropArea; anchors.fill: parent
                        onClicked: { if (serialManager) serialManager.refreshPorts(); portPopup.open() }
                    }
                }
                Popup {
                    id: portPopup; x: 0; y: 34; width: 122; padding: 2
                    background: Rectangle { color: colPanel; radius: 0; border.color: colAccent; border.width: 1 }
                    Column {
                        width: parent.width
                        Repeater {
                            model: serialManager ? serialManager.availablePorts : ["COM5"]
                            delegate: Rectangle {
                                width: 118; height: 30; color: portItemArea.containsMouse ? colBtnHover : colPanel
                                border.color: colInputBorder; border.width: 1
                                Text { anchors.centerIn: parent; text: modelData; font.pixelSize: 14; font.family: monoFont; color: colText }
                                MouseArea {
                                    id: portItemArea; anchors.fill: parent; hoverEnabled: true
                                    onClicked: { portField.text = modelData; portPopup.close() }
                                }
                            }
                        }
                    }
                }
            }
            Rectangle {
                width: 26; height: 26; radius: 0
                border.color: colInputBorder; border.width: 2
                color: root.lampMainLoop ? colLampOn : colLampOff
                anchors.verticalCenter: parent.verticalCenter
            }
            Text { text: "BAUD"; font.pixelSize: 20; font.family: monoFont; color: colLabel; anchors.verticalCenter: parent.verticalCenter }
            Row {
                spacing: 0; anchors.verticalCenter: parent.verticalCenter
                TextField {
                    id: baudField; width: 100; height: 34; font.pixelSize: 16; font.family: monoFont
                    text: "115200"; readOnly: true; horizontalAlignment: Text.AlignHCenter
                    color: colAccent
                    background: Rectangle { color: colInputBg; radius: 0; border.color: colInputBorder; border.width: 1 }
                }
                Rectangle {
                    width: 22; height: 34; radius: 0; color: baudDropArea.pressed ? colBtnHover : colBtn
                    border.color: colInputBorder; border.width: 1
                    Text { anchors.centerIn: parent; text: "\u25BC"; font.pixelSize: 10; color: colText }
                    MouseArea { id: baudDropArea; anchors.fill: parent; onClicked: baudPopup.open() }
                }
                Popup {
                    id: baudPopup; x: 0; y: 34; width: 122; padding: 2
                    background: Rectangle { color: colPanel; radius: 0; border.color: colAccent; border.width: 1 }
                    Column {
                        width: parent.width
                        Repeater {
                            model: ["9600", "19200", "38400", "57600", "115200"]
                            delegate: Rectangle {
                                width: 118; height: 30; color: baudItemArea.containsMouse ? colBtnHover : colPanel
                                border.color: colInputBorder; border.width: 1
                                Text { anchors.centerIn: parent; text: modelData; font.pixelSize: 14; font.family: monoFont; color: colText }
                                MouseArea {
                                    id: baudItemArea; anchors.fill: parent; hoverEnabled: true
                                    onClicked: { baudField.text = modelData; baudPopup.close() }
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
        x: 1270; y: 152
        width: 640; height: 122
        label: Text { text: "[ SENSOR DATA ]"; font.pixelSize: 22; font.bold: true; font.family: monoFont; color: colAccent }
        background: Rectangle { color: colPanel; radius: 0; border.color: colInputBorder; border.width: 1 }

        Grid {
            anchors.fill: parent; columns: 4; rowSpacing: 10; columnSpacing: 15
            Text { text: "Roll Angle"; font.pixelSize: 20; font.family: monoFont; width: 140; color: colLabel }
            Text { text: rollAngleValue.toFixed(1) + " \u00B0"; font.pixelSize: 22; font.bold: true; font.family: monoFont; width: 100; horizontalAlignment: Text.AlignRight; color: colAccent }
            Text { text: "Wheel RPM1"; font.pixelSize: 20; font.family: monoFont; width: 150; color: colLabel }
            Text { text: (serialManager ? serialManager.wheel1Rpm : 0) + " rpm"; font.pixelSize: 22; font.bold: true; font.family: monoFont; width: 120; horizontalAlignment: Text.AlignRight; color: colAccent }
            Text { text: "Gimbal Angle"; font.pixelSize: 20; font.family: monoFont; width: 140; color: colLabel }
            Text { text: gimbalAngleValue.toFixed(1) + " \u00B0"; font.pixelSize: 22; font.bold: true; font.family: monoFont; width: 100; horizontalAlignment: Text.AlignRight; color: colAccent }
            Text { text: "Wheel RPM2"; font.pixelSize: 20; font.family: monoFont; width: 150; color: colLabel }
            Text { text: (serialManager ? serialManager.wheel2Rpm : 0) + " rpm"; font.pixelSize: 22; font.bold: true; font.family: monoFont; width: 120; horizontalAlignment: Text.AlignRight; color: colAccent }
        }
    }

    // ── Control System ──
    GroupBox {
        id: controlBox
        x: 1270; y: 280
        width: 640; height: 148
        label: Text { text: "[ CONTROL SYSTEM ]"; font.pixelSize: 22; font.bold: true; font.family: monoFont; color: colAccent }
        background: Rectangle { color: colPanel; radius: 0; border.color: colInputBorder; border.width: 1 }

        Column {
            anchors.fill: parent; spacing: 10
            Row {
                id: controlRow1; spacing: 10
                Text { text: "WHEEL RPM"; font.pixelSize: 20; font.family: monoFont; color: colLabel; anchors.verticalCenter: parent.verticalCenter }
                Row {
                    spacing: 0; anchors.verticalCenter: parent.verticalCenter
                    TextField {
                        id: rpmField; width: 90; height: 40; text: "0"; font.pixelSize: 20; font.family: monoFont; horizontalAlignment: Text.AlignHCenter
                        color: colAccent; validator: IntValidator { bottom: 0; top: 10000 }
                        background: Rectangle { color: colInputBg; radius: 0; border.color: colInputBorder; border.width: 1 }
                        onAccepted: rpmSendTimer.restart()
                    }
                    Column {
                        spacing: 0
                        Rectangle {
                            width: 20; height: 20; radius: 0; color: rpmUp.pressed ? colBtnHover : colBtn; border.color: colInputBorder; border.width: 1
                            Text { anchors.centerIn: parent; text: "\u25B2"; font.pixelSize: 7; color: colAccent }
                            MouseArea { id: rpmUp; anchors.fill: parent; onClicked: { rpmField.text = String(Math.min(10000, Number(rpmField.text) + 100)); rpmSendTimer.restart() } }
                        }
                        Rectangle {
                            width: 20; height: 20; radius: 0; color: rpmDn.pressed ? colBtnHover : colBtn; border.color: colInputBorder; border.width: 1
                            Text { anchors.centerIn: parent; text: "\u25BC"; font.pixelSize: 7; color: colAccent }
                            MouseArea { id: rpmDn; anchors.fill: parent; onClicked: { rpmField.text = String(Math.max(0, Number(rpmField.text) - 100)); rpmSendTimer.restart() } }
                        }
                    }
                }
                Item { width: 15; height: 1 }
                Text { text: "CTRL_FACTOR"; font.pixelSize: 20; font.family: monoFont; color: colLabel; anchors.verticalCenter: parent.verticalCenter }
                TextField {
                    width: 75; height: 40; text: "2.5"; font.pixelSize: 20; font.family: monoFont; horizontalAlignment: Text.AlignHCenter
                    color: colAccent
                    background: Rectangle { color: colInputBg; radius: 0; border.color: colInputBorder; border.width: 1 }
                }
            }
            Item {
                width: parent.width; height: 45
                Text { id: dataFileLabel; text: "DATA FILE"; font.pixelSize: 20; font.family: monoFont; color: colLabel; anchors.verticalCenter: parent.verticalCenter }
                Rectangle {
                    id: startBtn
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    width: 140; height: 40; radius: 0
                    border.color: root.isRunning ? "#e84040" : colAccent; border.width: 2
                    color: root.isRunning
                        ? (startBtnArea.pressed ? "#8b0000" : "#b22222")
                        : (startBtnArea.pressed ? "#c48800" : colBtn)
                    Text { anchors.centerIn: parent; text: root.isRunning ? "STOP" : "START"; font.pixelSize: 20; font.bold: true; font.family: monoFont; font.letterSpacing: 2; color: root.isRunning ? "#fff" : colAccent }
                    MouseArea {
                        id: startBtnArea; anchors.fill: parent
                        onClicked: {
                            if (!root.isRunning) {
                                if (serialManager) {
                                    if (!serialManager.connected)
                                        serialManager.connectPort(portField.text, Number(baudField.text))
                                    serialManager.sendRPM(Number(rpmField.text))
                                    serialManager.setBalancingPID(Number(kpField.text), Number(kiField.text), Number(kdField.text), Number(gainField.text))
                                    serialManager.startBalancing()
                                    serialManager.startRecording(dataFileField.text)
                                    appendToLog(pidLogModel, "TX: B1 (START)")
                                }
                            } else {
                                if (serialManager && serialManager.connected) {
                                    serialManager.stopBalancing()
                                    serialManager.stopRecording()
                                    appendToLog(pidLogModel, "TX: B0 (STOP)")
                                }
                            }
                            root.isRunning = !root.isRunning
                        }
                    }
                }
                Rectangle {
                    id: browseBtn
                    anchors.right: startBtn.left; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                    width: 40; height: 40; radius: 0; color: browseBtnArea.pressed ? colBtnHover : colBtn
                    border.color: colInputBorder; border.width: 1
                    Text { anchors.centerIn: parent; text: "..."; font.pixelSize: 16; font.family: monoFont; color: colText }
                    MouseArea { id: browseBtnArea; anchors.fill: parent; onClicked: folderDialog.open() }
                }
                TextField {
                    id: dataFileField
                    anchors.left: dataFileLabel.right; anchors.leftMargin: 10
                    anchors.right: browseBtn.left; anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    height: 40; font.pixelSize: 14; font.family: monoFont; horizontalAlignment: Text.AlignLeft
                    text: serialManager ? serialManager.dataFolderPath() : ""
                    color: colText; readOnly: true
                    background: Rectangle { color: colInputBg; radius: 0; border.color: colInputBorder; border.width: 1 }
                }
                FolderDialog {
                    id: folderDialog
                    title: "Select Data Folder"
                    currentFolder: dataFileField.text ? ("file:///" + dataFileField.text) : ""
                    onAccepted: {
                        var path = selectedFolder.toString().replace("file:///", "")
                        dataFileField.text = path
                    }
                }
            }
        }
    }

    // ── Performance Metrics ──
    GroupBox {
        id: perfBox
        x: 1270; y: 434
        width: 640; height: 141
        label: Text { text: "[ PERFORMANCE ]"; font.pixelSize: 22; font.bold: true; font.family: monoFont; color: colAccent }
        background: Rectangle { color: colPanel; radius: 0; border.color: colInputBorder; border.width: 1 }

        Column {
            anchors.fill: parent; spacing: 8
            Row {
                anchors.horizontalCenter: parent.horizontalCenter; spacing: 15
                Text { text: "Kp"; font.pixelSize: 22; font.bold: true; font.family: monoFont; color: colLabel; anchors.verticalCenter: parent.verticalCenter }
                Row {
                    spacing: 0
                    TextField {
                        id: kpField; width: 75; height: 40; text: "50"; font.pixelSize: 20; font.family: monoFont; horizontalAlignment: Text.AlignHCenter
                        color: colAccent
                        background: Rectangle { color: colInputBg; radius: 0; border.color: colInputBorder; border.width: 1 }
                        onAccepted: pidSendTimer.restart()
                    }
                    Column {
                        spacing: 0
                        Rectangle {
                            width: 20; height: 20; radius: 0; color: kpUp.pressed ? colBtnHover : colBtn; border.color: colInputBorder; border.width: 1
                            Text { anchors.centerIn: parent; text: "\u25B2"; font.pixelSize: 7; color: colAccent }
                            MouseArea { id: kpUp; anchors.fill: parent; onClicked: { kpField.text = String(Number(kpField.text) + 1); pidSendTimer.restart() } }
                        }
                        Rectangle {
                            width: 20; height: 20; radius: 0; color: kpDn.pressed ? colBtnHover : colBtn; border.color: colInputBorder; border.width: 1
                            Text { anchors.centerIn: parent; text: "\u25BC"; font.pixelSize: 7; color: colAccent }
                            MouseArea { id: kpDn; anchors.fill: parent; onClicked: { kpField.text = String(Math.max(0, Number(kpField.text) - 1)); pidSendTimer.restart() } }
                        }
                    }
                }
                Text { text: "Ki"; font.pixelSize: 22; font.bold: true; font.family: monoFont; color: colLabel; anchors.verticalCenter: parent.verticalCenter }
                Row {
                    spacing: 0
                    TextField {
                        id: kiField; width: 75; height: 40; text: "0.03"; font.pixelSize: 20; font.family: monoFont; horizontalAlignment: Text.AlignHCenter
                        color: colAccent
                        background: Rectangle { color: colInputBg; radius: 0; border.color: colInputBorder; border.width: 1 }
                        onAccepted: pidSendTimer.restart()
                    }
                    Column {
                        spacing: 0
                        Rectangle {
                            width: 20; height: 20; radius: 0; color: kiUp.pressed ? colBtnHover : colBtn; border.color: colInputBorder; border.width: 1
                            Text { anchors.centerIn: parent; text: "\u25B2"; font.pixelSize: 7; color: colAccent }
                            MouseArea { id: kiUp; anchors.fill: parent; onClicked: { kiField.text = String((Number(kiField.text) + 0.01).toFixed(2)); pidSendTimer.restart() } }
                        }
                        Rectangle {
                            width: 20; height: 20; radius: 0; color: kiDn.pressed ? colBtnHover : colBtn; border.color: colInputBorder; border.width: 1
                            Text { anchors.centerIn: parent; text: "\u25BC"; font.pixelSize: 7; color: colAccent }
                            MouseArea { id: kiDn; anchors.fill: parent; onClicked: { kiField.text = String(Math.max(0, (Number(kiField.text) - 0.01)).toFixed(2)); pidSendTimer.restart() } }
                        }
                    }
                }
                Text { text: "Kd"; font.pixelSize: 22; font.bold: true; font.family: monoFont; color: colLabel; anchors.verticalCenter: parent.verticalCenter }
                Row {
                    spacing: 0
                    TextField {
                        id: kdField; width: 75; height: 40; text: "20"; font.pixelSize: 20; font.family: monoFont; horizontalAlignment: Text.AlignHCenter
                        color: colAccent
                        background: Rectangle { color: colInputBg; radius: 0; border.color: colInputBorder; border.width: 1 }
                        onAccepted: pidSendTimer.restart()
                    }
                    Column {
                        spacing: 0
                        Rectangle {
                            width: 20; height: 20; radius: 0; color: kdUp.pressed ? colBtnHover : colBtn; border.color: colInputBorder; border.width: 1
                            Text { anchors.centerIn: parent; text: "\u25B2"; font.pixelSize: 7; color: colAccent }
                            MouseArea { id: kdUp; anchors.fill: parent; onClicked: { kdField.text = String(Number(kdField.text) + 1); pidSendTimer.restart() } }
                        }
                        Rectangle {
                            width: 20; height: 20; radius: 0; color: kdDn.pressed ? colBtnHover : colBtn; border.color: colInputBorder; border.width: 1
                            Text { anchors.centerIn: parent; text: "\u25BC"; font.pixelSize: 7; color: colAccent }
                            MouseArea { id: kdDn; anchors.fill: parent; onClicked: { kdField.text = String(Math.max(0, Number(kdField.text) - 1)); pidSendTimer.restart() } }
                        }
                    }
                }
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter; spacing: 8
                Text { text: "GIMBAL RESET GAIN"; font.pixelSize: 20; font.family: monoFont; color: colLabel; anchors.verticalCenter: parent.verticalCenter }
                Row {
                    spacing: 0
                    TextField {
                        id: gainField; width: 75; height: 40; text: "0.03"; font.pixelSize: 20; font.family: monoFont; horizontalAlignment: Text.AlignHCenter
                        color: colAccent
                        background: Rectangle { color: colInputBg; radius: 0; border.color: colInputBorder; border.width: 1 }
                        onAccepted: pidSendTimer.restart()
                    }
                    Column {
                        spacing: 0
                        Rectangle {
                            width: 20; height: 20; radius: 0; color: gainUp.pressed ? colBtnHover : colBtn; border.color: colInputBorder; border.width: 1
                            Text { anchors.centerIn: parent; text: "\u25B2"; font.pixelSize: 7; color: colAccent }
                            MouseArea { id: gainUp; anchors.fill: parent; onClicked: { gainField.text = String((Number(gainField.text) + 0.01).toFixed(2)); pidSendTimer.restart() } }
                        }
                        Rectangle {
                            width: 20; height: 20; radius: 0; color: gainDn.pressed ? colBtnHover : colBtn; border.color: colInputBorder; border.width: 1
                            Text { anchors.centerIn: parent; text: "\u25BC"; font.pixelSize: 7; color: colAccent }
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
        x: 1270; y: 581
        width: 640; height: 493
        label: Text { text: "[ TORQUE TREND ]"; font.pixelSize: 22; font.bold: true; font.family: monoFont; color: colAccent }
        background: Rectangle { color: colPanel; radius: 0; border.color: colInputBorder; border.width: 1 }

        Item {
            anchors.fill: parent
            Row {
                anchors.top: parent.top; anchors.right: parent.right; spacing: 8; z: 1
                Text { text: "TORQUE"; font.pixelSize: 22; font.bold: true; font.family: monoFont; color: colLabel }
                Text { text: torqueValue.toFixed(2) + " Nm"; font.pixelSize: 22; font.bold: true; font.family: monoFont; color: "#e84040" }
            }
            ChartView {
                anchors.fill: parent; anchors.topMargin: 30
                antialiasing: true; backgroundColor: colChartBg; legend.visible: false
                plotAreaColor: colChartBg; titleColor: colText
                ValuesAxis { id: torqueAxisX; min: 0; max: 20; titleText: "Time"; labelsFont.pixelSize: 11; labelsFont.family: monoFont; gridLineColor: colGrid; labelsColor: colLabel; titleBrush: colLabel }
                ValuesAxis { id: torqueAxisY; min: -1; max: 1; tickCount: 11; titleText: "Torque (Nm)"; labelsFont.pixelSize: 11; labelsFont.family: monoFont; gridLineColor: colGrid; labelsColor: colLabel; titleBrush: colLabel }
                LineSeries { id: torqueSeries; color: "#e84040"; width: 2; axisX: torqueAxisX; axisY: torqueAxisY }
            }
        }
    }
}
