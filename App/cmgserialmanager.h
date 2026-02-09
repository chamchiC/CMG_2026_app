#ifndef CMGSERIALMANAGER_H
#define CMGSERIALMANAGER_H

#include <QObject>
#include <QSerialPort>
#include <QSerialPortInfo>
#include <QByteArray>
#include <QStringList>
#include <QTimer>
#include <QFile>
#include <QTextStream>
#include <QDir>
#include <QDateTime>

/**
 * CMGSerialManager
 *
 * HMI 명령 전송 (ASCII)  +  텔레메트리 수신/파싱 (110-byte binary)
 * 사용자 매뉴얼 02_사용자_매뉴얼.md 기준 구현
 *
 * 바이너리 패킷: 0xAA 0x55 + 108 bytes + 1 byte checksum = 110 bytes
 * ASCII 라인:  LOG:, STATUS: 등 줄바꿈으로 구분
 */
class CMGSerialManager : public QObject
{
    Q_OBJECT

    // ── Connection ──
    Q_PROPERTY(bool connected READ connected NOTIFY connectionChanged)
    Q_PROPERTY(QString connectionStatus READ connectionStatus NOTIFY connectionChanged)
    Q_PROPERTY(QStringList availablePorts READ availablePorts NOTIFY portsChanged)

    // ── Telemetry: IMU ──
    Q_PROPERTY(double roll   READ roll   NOTIFY telemetryUpdated)
    Q_PROPERTY(double pitch  READ pitch  NOTIFY telemetryUpdated)
    Q_PROPERTY(double yaw    READ yaw    NOTIFY telemetryUpdated)
    Q_PROPERTY(double gyroX  READ gyroX  NOTIFY telemetryUpdated)
    Q_PROPERTY(double gyroY  READ gyroY  NOTIFY telemetryUpdated)
    Q_PROPERTY(double gyroZ  READ gyroZ  NOTIFY telemetryUpdated)
    Q_PROPERTY(double accelX READ accelX NOTIFY telemetryUpdated)
    Q_PROPERTY(double accelY READ accelY NOTIFY telemetryUpdated)

    // ── Telemetry: Wheel ──
    Q_PROPERTY(int    targetRPM  READ targetRPM  NOTIFY telemetryUpdated)
    Q_PROPERTY(int    wheel1Rpm  READ wheel1Rpm  NOTIFY telemetryUpdated)
    Q_PROPERTY(int    wheel2Rpm  READ wheel2Rpm  NOTIFY telemetryUpdated)
    Q_PROPERTY(double wheel1Pwm  READ wheel1Pwm  NOTIFY telemetryUpdated)
    Q_PROPERTY(double wheel2Pwm  READ wheel2Pwm  NOTIFY telemetryUpdated)
    Q_PROPERTY(int    wheelState READ wheelState NOTIFY telemetryUpdated)

    // ── Telemetry: Gimbal ──
    Q_PROPERTY(double gimbalAngle    READ gimbalAngle    NOTIFY telemetryUpdated)
    Q_PROPERTY(double gimbalTarget   READ gimbalTarget   NOTIFY telemetryUpdated)
    Q_PROPERTY(double gimbalVelocity READ gimbalVelocity NOTIFY telemetryUpdated)

    // ── Telemetry: Balancing ──
    Q_PROPERTY(bool   balancing READ balancing NOTIFY telemetryUpdated)
    Q_PROPERTY(double balKp     READ balKp     NOTIFY telemetryUpdated)
    Q_PROPERTY(double balKi     READ balKi     NOTIFY telemetryUpdated)
    Q_PROPERTY(double balKd     READ balKd     NOTIFY telemetryUpdated)
    Q_PROPERTY(double washout   READ washout   NOTIFY telemetryUpdated)

    // ── Telemetry: Wheel PID ──
    Q_PROPERTY(double wheelKp READ wheelKp NOTIFY telemetryUpdated)
    Q_PROPERTY(double wheelKi READ wheelKi NOTIFY telemetryUpdated)
    Q_PROPERTY(double wheelKd READ wheelKd NOTIFY telemetryUpdated)

    // ── Telemetry: Status ──
    Q_PROPERTY(int     commBits    READ commBits    NOTIFY telemetryUpdated)
    Q_PROPERTY(quint32 timestampMs READ timestampMs NOTIFY telemetryUpdated)

    // ── Diagnostic ──
    Q_PROPERTY(int packetCount READ packetCount NOTIFY telemetryUpdated)

public:
    explicit CMGSerialManager(QObject *parent = nullptr);
    ~CMGSerialManager();

    // ── Property Getters ──
    bool connected() const;
    QString connectionStatus() const;
    QStringList availablePorts() const;

    double roll()   const;
    double pitch()  const;
    double yaw()    const;
    double gyroX()  const;
    double gyroY()  const;
    double gyroZ()  const;
    double accelX() const;
    double accelY() const;

    int    targetRPM()  const;
    int    wheel1Rpm()  const;
    int    wheel2Rpm()  const;
    double wheel1Pwm()  const;
    double wheel2Pwm()  const;
    int    wheelState() const;

    double gimbalAngle()    const;
    double gimbalTarget()   const;
    double gimbalVelocity() const;

    bool   balancing() const;
    double balKp()     const;
    double balKi()     const;
    double balKd()     const;
    double washout()   const;

    double wheelKp() const;
    double wheelKi() const;
    double wheelKd() const;

    int     commBits()    const;
    quint32 timestampMs() const;
    int     packetCount() const;

    // ── QML Invokable: Connection ──
    Q_INVOKABLE void connectPort(const QString &portName, int baudRate);
    Q_INVOKABLE void disconnectPort();
    Q_INVOKABLE void refreshPorts();

    // ── QML Invokable: HMI Commands (매뉴얼 1.2 ~ 1.4) ──
    Q_INVOKABLE void sendRPM(int rpm);           // R<값>
    Q_INVOKABLE void startWheel();               // S1
    Q_INVOKABLE void stopWheel();                // S0
    Q_INVOKABLE void emergencyStop();            // E
    Q_INVOKABLE void resetEmergency();           // X
    Q_INVOKABLE void queryStatus();              // ?
    Q_INVOKABLE void setGimbalAngle(double angle); // A<각도>
    Q_INVOKABLE void startBalancing();           // B1
    Q_INVOKABLE void stopBalancing();            // B0
    Q_INVOKABLE void setBalancingPID(double kp, double ki, double kd, double washoutGain); // K<Kp>,<Ki>,<Kd>,<Washout>
    Q_INVOKABLE void setWheelPID(double kp, double ki, double kd); // WK<Kp>,<Ki>,<Kd>
    Q_INVOKABLE void setWashoutGain(double gain); // W<값>
    Q_INVOKABLE void sendRawCommand(const QString &cmd);

    // ── CSV Recording ──
    Q_INVOKABLE void startRecording(const QString &folderPath);
    Q_INVOKABLE void stopRecording();
    Q_INVOKABLE bool isRecording() const;

signals:
    void connectionChanged();
    void portsChanged();
    void telemetryUpdated();
    void logReceived(const QString &message);
    void statusReceived(const QString &message);

private slots:
    void onReadyRead();
    void onErrorOccurred(QSerialPort::SerialPortError error);
    void tryReconnect();
    void onDataTimeout();

private:
    void sendCommand(const QString &cmd);
    void processBuffer();
    void parseTelemetryPacket(const QByteArray &packet);
    void processAsciiLine(const QString &line);
    void startReconnectTimer();
    void stopReconnectTimer();
    void setConnectionStatus(const QString &status);

    QSerialPort *m_serial;
    QByteArray   m_buffer;
    QByteArray   m_asciiCarry;   // 매직 앞에서 잘린 ASCII 조각 보관 (split line 복원용)

    // ── 자동 재연결 ──
    QTimer      *m_reconnectTimer = nullptr;
    QString      m_lastPortName;
    int          m_lastBaudRate = 115200;
    bool         m_autoReconnect = false;   // connectPort 호출 후 활성화

    // ── 연결 상태 감시 ──
    QTimer      *m_dataTimeoutTimer = nullptr;
    QString      m_connectionStatus = "Disconnected";
    bool         m_dataReceived = false;     // 유효 패킷/ASCII 수신 여부

    // ── CSV 녹화 ──
    QFile       *m_csvFile = nullptr;
    QTextStream *m_csvStream = nullptr;
    bool         m_recording = false;
    quint32      m_recordStartTs = 0;   // 녹화 시작 시 MCU timestamp

    // ── 텔레메트리 패킷 구조 (110 bytes, Little-endian) ──
    struct TelemetryData {
        quint32 timestampMs   = 0;
        float roll = 0, pitch = 0, yaw = 0;
        float gyroX = 0, gyroY = 0, gyroZ = 0;
        float accelX = 0, accelY = 0;
        qint32 targetRPM = 0;
        qint32 wheel1Rpm = 0, wheel2Rpm = 0;
        float wheel1Pwm = 0, wheel2Pwm = 0;
        quint8 wheelState = 0;
        float gimbalAngle = 0, gimbalTarget = 0, gimbalVelocity = 0;
        float gimbal1 = 0, gimbal2 = 0;
        quint8 balancing = 0;
        float balKp = 0, balKi = 0, balKd = 0, washout = 0;
        float wheelKp = 0, wheelKi = 0, wheelKd = 0;
        quint8 commBits = 0;
    } m_telemetry;

    QStringList m_ports;
    int m_packetCount = 0;
    int m_checksumFails = 0;
    qint64 m_totalBytesReceived = 0;
};

#endif // CMGSERIALMANAGER_H
