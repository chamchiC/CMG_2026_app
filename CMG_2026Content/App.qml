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

}
