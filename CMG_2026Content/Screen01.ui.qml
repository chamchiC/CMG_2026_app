/*
This is a UI file (.ui.qml) that is intended to be edited in Qt Design Studio only.
It is supposed to be strictly declarative and only uses a subset of QML. If you edit
this file manually, you might introduce QML code that is not supported by Qt Design Studio.
Check out https://doc.qt.io/qtcreator/creator-quick-ui-forms.html for details on .ui.qml files.
*/

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCharts
import CMG_2026

Rectangle {
    id: rectangle
    width: Constants.width
    height: Constants.height
    color: "#ffffff"

    GroupBox {
        id: groupBox
        x: 8
        y: 80
        width: 455
        height: 135
        title: qsTr("Group Box")
    }

    TextEdit {
        id: textEdit
        x: 8
        y: 8
        width: 1904
        height: 66
        text: qsTr("Text Edit")
        font.pixelSize: 12
    }

    GroupBox {
        id: groupBox1
        x: 469
        y: 80
        width: 455
        height: 135
        title: qsTr("Group Box")
    }
}
