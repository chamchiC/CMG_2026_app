#include "serialporthelper.h"

SerialPortHelper::SerialPortHelper(QObject *parent)
    : QObject(parent)
{
    refresh();
}

QStringList SerialPortHelper::availablePorts() const
{
    return m_ports;
}

void SerialPortHelper::refresh()
{
    QStringList ports;
    const auto infos = QSerialPortInfo::availablePorts();
    for (const QSerialPortInfo &info : infos) {
        ports << info.portName();   // "COM3", "COM5" 등
    }
    ports.sort();

    if (m_ports != ports) {
        m_ports = ports;
        emit portsChanged();
    }
}
