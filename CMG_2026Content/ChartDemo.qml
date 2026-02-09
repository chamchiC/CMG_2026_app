import QtQuick

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: "#f0f0f0"

    // ── 상단 제목 바 ──
    Rectangle {
        id: titleBar
        x: 10
        y: 10
        width: 1900
        height: 96
        color: "#ffffff"
        radius: 4
        border.color: "#3a3a5c"
        border.width: 3
    }

    // ── 좌측 패널 ──
    Rectangle {
        id: leftPanel
        x: 10
        y: 112
        width: 1229
        height: 920
        color: "#ffffff"
        radius: 4
        border.color: "#3a3a5c"
        border.width: 3
    }

    // ── 우측 패널 ──
    Rectangle {
        id: rightPanel
        x: 1245
        y: 112
        width: 665
        height: 920
        color: "#ffffff"
        radius: 4
        border.color: "#3a3a5c"
        border.width: 3
    }
}
