#ifndef SERIALPORTHELPER_H
#define SERIALPORTHELPER_H

#include <QObject>
#include <QStringList>
#include <QSerialPortInfo>

class SerialPortHelper : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QStringList availablePorts READ availablePorts NOTIFY portsChanged)

public:
    explicit SerialPortHelper(QObject *parent = nullptr);

    QStringList availablePorts() const;

    // QML에서 호출: ComboBox 열릴 때 포트 목록 새로고침
    Q_INVOKABLE void refresh();

signals:
    void portsChanged();

private:
    QStringList m_ports;
};

#endif // SERIALPORTHELPER_H
