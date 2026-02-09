import QtQuick
import QtQuick.Controls
import CMG_2026

Window {
    id: mainWindow
    width: 1920
    height: 1080

    visible: true
    visibility: Window.Maximized
    title: "CMG - Control Moment Gyroscope System"
    color: "#e8e8e8"

    // 메인 모니터링 화면 (serialManager로 직접 데이터 수신)
    CMGMainView {
        id: mainView
        anchors.fill: parent
    }

    // ── 두 번째 창: 컨트롤러 (비활성화 - serialManager로 대체) ──
    Window {
        id: controllerWindow
        width: 500
        height: 750
        visible: false  // 시리얼 통신으로 대체됨
        title: "CMG - Graph Controller"
        x: 50
        y: 50

        CMGController {
            id: controllerView
            anchors.fill: parent

            onStartClicked: mainView.isRunning = true
            onStopClicked: mainView.isRunning = false
            onResetClicked: mainView.resetAll()
        }
    }
}
