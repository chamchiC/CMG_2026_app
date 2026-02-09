#include "cmgserialmanager.h"
#include <QDebug>
#include <cstring>

static const quint8 MAGIC_BYTE_1 = 0xAA;
static const quint8 MAGIC_BYTE_2 = 0x55;
static const int    PACKET_SIZE  = 110;

// ═══════════════════════════════════════════════
// 생성자 / 소멸자
// ═══════════════════════════════════════════════

CMGSerialManager::CMGSerialManager(QObject *parent)
    : QObject(parent)
    , m_serial(new QSerialPort(this))
    , m_reconnectTimer(new QTimer(this))
    , m_dataTimeoutTimer(new QTimer(this))
{
    connect(m_serial, &QSerialPort::readyRead,
            this, &CMGSerialManager::onReadyRead);
    connect(m_serial, &QSerialPort::errorOccurred,
            this, &CMGSerialManager::onErrorOccurred);

    // 재연결 타이머: 2초 간격
    m_reconnectTimer->setInterval(2000);
    connect(m_reconnectTimer, &QTimer::timeout,
            this, &CMGSerialManager::tryReconnect);

    // 데이터 수신 감시 타이머: 3초 내 유효 데이터 없으면 경고
    m_dataTimeoutTimer->setInterval(3000);
    m_dataTimeoutTimer->setSingleShot(true);
    connect(m_dataTimeoutTimer, &QTimer::timeout,
            this, &CMGSerialManager::onDataTimeout);

    refreshPorts();
    qWarning() << "CMGSerialManager: initialized, ports:" << m_ports;
}

CMGSerialManager::~CMGSerialManager()
{
    if (m_serial->isOpen())
        m_serial->close();
}

// ═══════════════════════════════════════════════
// Connection
// ═══════════════════════════════════════════════

bool CMGSerialManager::connected() const
{
    return m_serial->isOpen() && m_dataReceived;
}

QString CMGSerialManager::connectionStatus() const
{
    return m_connectionStatus;
}

void CMGSerialManager::setConnectionStatus(const QString &status)
{
    if (m_connectionStatus != status) {
        m_connectionStatus = status;
        emit connectionChanged();
    }
}

QStringList CMGSerialManager::availablePorts() const
{
    return m_ports;
}

void CMGSerialManager::refreshPorts()
{
    QStringList ports;
    const auto infos = QSerialPortInfo::availablePorts();
    for (const QSerialPortInfo &info : infos)
        ports << info.portName();
    ports.sort();

    if (m_ports != ports) {
        m_ports = ports;
        emit portsChanged();
    }
}

void CMGSerialManager::connectPort(const QString &portName, int baudRate)
{
    if (m_serial->isOpen())
        disconnectPort();

    // 재연결용 파라미터 기억
    m_lastPortName = portName;
    m_lastBaudRate = baudRate;
    m_autoReconnect = true;

    m_serial->setPortName(portName);
    m_serial->setBaudRate(baudRate);
    m_serial->setDataBits(QSerialPort::Data8);
    m_serial->setParity(QSerialPort::NoParity);
    m_serial->setStopBits(QSerialPort::OneStop);
    m_serial->setFlowControl(QSerialPort::NoFlowControl);

    if (m_serial->open(QIODevice::ReadWrite)) {
        // 시리얼 입출력 버퍼 클리어 (잔여 데이터 방지)
        m_serial->clear();
        stopReconnectTimer();
        m_buffer.clear();
        m_asciiCarry.clear();
        m_packetCount = 0;
        m_checksumFails = 0;
        m_totalBytesReceived = 0;
        m_dataReceived = false;
        qWarning() << "CMGSerialManager: Port opened:" << portName << "@" << baudRate;
        setConnectionStatus("Connecting: " + portName + " @ " + QString::number(baudRate));
        emit logReceived("Connecting: " + portName + " @ " + QString::number(baudRate));
        m_dataTimeoutTimer->start();  // 3초 후 데이터 없으면 경고
    } else {
        qWarning() << "CMGSerialManager: FAILED to open" << portName << "-" << m_serial->errorString();
        setConnectionStatus("Failed: " + m_serial->errorString());
        emit logReceived("Connection failed: " + m_serial->errorString());
        startReconnectTimer();
    }
}

void CMGSerialManager::disconnectPort()
{
    // 수동 해제 → 자동 재연결 비활성화
    m_autoReconnect = false;
    stopReconnectTimer();
    m_dataTimeoutTimer->stop();

    if (m_serial->isOpen()) {
        m_serial->close();
        m_buffer.clear();
        m_asciiCarry.clear();
        m_dataReceived = false;
        qDebug() << "CMGSerialManager: Disconnected";
        setConnectionStatus("Disconnected");
        emit logReceived("Disconnected");
    }
}

// ═══════════════════════════════════════════════
// HMI Commands  (매뉴얼 §1.2 ~ §1.4)
// ═══════════════════════════════════════════════

void CMGSerialManager::sendCommand(const QString &cmd)
{
    if (!m_serial->isOpen()) {
        emit logReceived("Not connected");
        return;
    }
    QByteArray data = cmd.toUtf8() + "\n";
    m_serial->write(data);
    qDebug() << "TX:" << cmd;
}

// §1.2  휠 모터 제어
void CMGSerialManager::sendRPM(int rpm)
{
    sendCommand("R" + QString::number(qMax(0, rpm)));
}

void CMGSerialManager::startWheel()    { sendCommand("S1"); }
void CMGSerialManager::stopWheel()     { sendCommand("S0"); }
void CMGSerialManager::emergencyStop() { sendCommand("E");  }
void CMGSerialManager::resetEmergency(){ sendCommand("X");  }
void CMGSerialManager::queryStatus()   { sendCommand("?");  }

// §1.3  짐벌 제어
void CMGSerialManager::setGimbalAngle(double angle)
{
    sendCommand("A" + QString::number(angle, 'f', 1));
}

// §1.4  밸런싱 제어
void CMGSerialManager::startBalancing() { sendCommand("B1"); }
void CMGSerialManager::stopBalancing()  { sendCommand("B0"); }

void CMGSerialManager::setBalancingPID(double kp, double ki, double kd, double washoutGain)
{
    // K<Kp>,<Ki>,<Kd>,<Washout>
    sendCommand(QString("K%1,%2,%3,%4")
                    .arg(kp, 0, 'f', 2)
                    .arg(ki, 0, 'f', 3)
                    .arg(kd, 0, 'f', 2)
                    .arg(washoutGain, 0, 'f', 3));
}

void CMGSerialManager::setWheelPID(double kp, double ki, double kd)
{
    // WK<Kp>,<Ki>,<Kd>
    sendCommand(QString("WK%1,%2,%3")
                    .arg(kp, 0, 'g', 6)
                    .arg(ki, 0, 'g', 6)
                    .arg(kd, 0, 'g', 6));
}

void CMGSerialManager::setWashoutGain(double gain)
{
    sendCommand("W" + QString::number(gain, 'f', 3));
}

void CMGSerialManager::sendRawCommand(const QString &cmd)
{
    sendCommand(cmd);
}

// ═══════════════════════════════════════════════
// Data Reception & Parsing
// ═══════════════════════════════════════════════

void CMGSerialManager::onReadyRead()
{
    QByteArray incoming = m_serial->readAll();
    m_buffer.append(incoming);

    // 디버그: 수신 바이트 수 (첫 수신 시만 표시, 이후 100패킷마다)
    m_totalBytesReceived += incoming.size();
    if (m_totalBytesReceived == incoming.size() || m_packetCount % 100 == 0) {
        QString rxMsg = QString("RX: %1 bytes, total: %2, buf: %3")
                            .arg(incoming.size()).arg(m_totalBytesReceived).arg(m_buffer.size());
        qWarning().noquote() << rxMsg;
        emit logReceived(rxMsg);
    }

    // 버퍼 오버플로 방지 (약 90 패킷분)
    if (m_buffer.size() > 10000) {
        // 최근 데이터 보존: 마지막 매직 위치부터 유지
        int lastMagic = -1;
        const int searchStart = qMax(0, m_buffer.size() - 500);
        for (int i = m_buffer.size() - 2; i >= searchStart; --i) {
            if (static_cast<quint8>(m_buffer[i])     == MAGIC_BYTE_1 &&
                static_cast<quint8>(m_buffer[i + 1]) == MAGIC_BYTE_2) {
                lastMagic = i;
                break;
            }
        }
        if (lastMagic >= 0) {
            QString msg = QString("Buffer overflow, keeping %1 bytes").arg(m_buffer.size() - lastMagic);
            qWarning().noquote() << "CMGSerialManager:" << msg;
            emit logReceived(msg);
            m_buffer = m_buffer.mid(lastMagic);
        } else {
            qWarning() << "CMGSerialManager: Buffer overflow, clearing";
            emit logReceived("Buffer overflow, clearing");
            m_buffer.clear();
        }
        m_asciiCarry.clear();
        return;
    }

    processBuffer();
}

void CMGSerialManager::onErrorOccurred(QSerialPort::SerialPortError error)
{
    if (error == QSerialPort::NoError)
        return;

    qWarning() << "CMGSerialManager: Error -" << m_serial->errorString();

    if (error != QSerialPort::TimeoutError)
        emit logReceived("Serial error: " + m_serial->errorString());

    // 디바이스 제거(케이블 분리 등) → 포트 닫고 자동 재연결 시작
    if (error == QSerialPort::ResourceError) {
        qWarning() << "CMGSerialManager: Device lost, will auto-reconnect";
        m_serial->close();
        m_buffer.clear();
        m_asciiCarry.clear();
        m_dataReceived = false;
        m_dataTimeoutTimer->stop();
        setConnectionStatus("Device lost — reconnecting...");
        emit logReceived("Device lost — reconnecting...");
        startReconnectTimer();
    }
}

void CMGSerialManager::onDataTimeout()
{
    // 포트는 열렸지만 유효 데이터가 3초간 없음
    if (m_serial->isOpen() && !m_dataReceived) {
        qWarning() << "CMGSerialManager: No valid data received — check wiring";
        setConnectionStatus("No data — check wiring (" + m_lastPortName + ")");
        emit logReceived("No data received — check wiring or port");
    }
}

/**
 * processBuffer()
 *
 * 바이너리 텔레메트리(0xAA 0x55 매직)와 ASCII 라인(\n)을 혼합 처리.
 * 매뉴얼 §2.2 ~ §2.3 참고.
 *
 * 알고리즘:
 *  1. 매직 바이트 0xAA 0x55 탐색
 *  2. 매직 이전 데이터 → ASCII 라인으로 파싱
 *  3. 매직부터 110바이트 읽기 → XOR 체크섬 검증
 *  4. 체크섬 실패 시 1바이트 건너뛰고 재동기
 */
/**
 * processBuffer()  — 매뉴얼 §2.3 권장 파싱
 *
 * 바이너리(0xAA 0x55 패킷)와 ASCII(\n 라인)를 명확히 분리.
 *
 * 알고리즘:
 *  1. 버퍼에서 매직(0xAA 0x55)과 줄바꿈(\n) 중 먼저 오는 것을 찾는다
 *  2. \n이 먼저 → 그 줄이 printable ASCII이면 텍스트로 처리, 아니면 버림
 *  3. 매직이 먼저 → 110바이트 읽기 → 체크섬 → 바이너리 패킷 파싱
 *  4. 매직 앞의 잔여 바이트는 패킷 경계 노이즈 → 버림
 *  5. 둘 다 없으면 대기
 */
void CMGSerialManager::processBuffer()
{
    while (m_buffer.size() >= 2) {

        // ── 매직과 줄바꿈 중 먼저 오는 것 탐색 ──
        int magicIdx = -1;
        int nlIdx    = -1;

        for (int i = 0; i < m_buffer.size(); ++i) {
            // 줄바꿈 탐색
            if (nlIdx < 0 && m_buffer[i] == '\n')
                nlIdx = i;

            // 매직 탐색
            if (magicIdx < 0 && i < m_buffer.size() - 1 &&
                static_cast<quint8>(m_buffer[i])     == MAGIC_BYTE_1 &&
                static_cast<quint8>(m_buffer[i + 1]) == MAGIC_BYTE_2)
                magicIdx = i;

            // 둘 다 찾았으면 중단
            if (magicIdx >= 0 && nlIdx >= 0) break;
        }

        // ── Case 1: \n이 매직보다 앞에 있음 → ASCII 라인 ──
        if (nlIdx >= 0 && (magicIdx < 0 || nlIdx < magicIdx)) {
            QByteArray lineBytes = m_buffer.left(nlIdx);
            m_buffer = m_buffer.mid(nlIdx + 1);

            // 이전에 매직 앞에서 잘린 ASCII 조각이 있으면 앞에 붙임
            if (!m_asciiCarry.isEmpty()) {
                lineBytes.prepend(m_asciiCarry);
                m_asciiCarry.clear();
            }

            // printable ASCII 체크 (80% 이상 printable이면 텍스트)
            if (!lineBytes.isEmpty()) {
                int printable = 0;
                for (char c : lineBytes) {
                    if (c >= 0x20 && c <= 0x7E) printable++;
                }
                if (printable * 100 >= lineBytes.size() * 80) {
                    // 앞뒤 non-printable 바이트 제거 (바이너리 노이즈 방지)
                    int start = 0;
                    while (start < lineBytes.size() &&
                           (static_cast<quint8>(lineBytes[start]) < 0x20 ||
                            static_cast<quint8>(lineBytes[start]) > 0x7E))
                        ++start;
                    int end = lineBytes.size() - 1;
                    while (end > start &&
                           (static_cast<quint8>(lineBytes[end]) < 0x20 ||
                            static_cast<quint8>(lineBytes[end]) > 0x7E))
                        --end;
                    lineBytes = lineBytes.mid(start, end - start + 1);

                    QString line = QString::fromUtf8(lineBytes).trimmed();
                    if (!line.isEmpty())
                        processAsciiLine(line);
                }
                // else: 바이너리 노이즈에 우연히 \n 포함 → 무시
            }
            continue;
        }

        // ── Case 2: 매직 발견 → 바이너리 패킷 ──
        if (magicIdx >= 0) {
            // 매직 앞 바이트: printable이 많으면 잘린 ASCII 조각일 수 있음 → 보관
            if (magicIdx > 0) {
                QByteArray prefix = m_buffer.left(magicIdx);
                m_buffer = m_buffer.mid(magicIdx);

                int printable = 0;
                for (char c : prefix)
                    if (c >= 0x20 && c <= 0x7E) printable++;

                if (printable > 0 && printable * 2 >= prefix.size()) {
                    // >50% printable → 잘린 ASCII 조각 가능성 → carry에 누적
                    m_asciiCarry.append(prefix);
                } else {
                    // 순수 바이너리 노이즈 → carry 초기화
                    m_asciiCarry.clear();
                }
                // carry 과다 누적 방지 (300바이트 이상이면 노이즈로 판단)
                if (m_asciiCarry.size() > 300)
                    m_asciiCarry.clear();
            }

            // 110바이트 필요
            if (m_buffer.size() < PACKET_SIZE)
                break;

            QByteArray packet = m_buffer.left(PACKET_SIZE);

            // ── XOR 체크섬 검증 ──
            quint8 checksumFull = 0;
            for (int i = 0; i < PACKET_SIZE - 1; ++i)
                checksumFull ^= static_cast<quint8>(packet[i]);

            quint8 checksumNoMagic = 0;
            for (int i = 2; i < PACKET_SIZE - 1; ++i)
                checksumNoMagic ^= static_cast<quint8>(packet[i]);

            quint8 expected = static_cast<quint8>(packet[PACKET_SIZE - 1]);

            if (checksumFull == expected || checksumNoMagic == expected) {
                m_packetCount++;
                parseTelemetryPacket(packet);
                m_buffer = m_buffer.mid(PACKET_SIZE);

                // 첫 유효 패킷 수신 → 연결 확정
                if (!m_dataReceived) {
                    m_dataReceived = true;
                    m_dataTimeoutTimer->stop();
                    setConnectionStatus("Connected: " + m_lastPortName + " @ " + QString::number(m_lastBaudRate));
                    emit logReceived("Connected: " + m_lastPortName + " @ " + QString::number(m_lastBaudRate));
                }

                if (m_packetCount <= 3 || m_packetCount % 500 == 0) {
                    QString pktMsg = QString("PKT #%1 ts=%2 roll=%3 gimbal=%4 %5")
                        .arg(m_packetCount).arg(m_telemetry.timestampMs)
                        .arg(m_telemetry.roll, 0, 'f', 2).arg(m_telemetry.gimbalAngle, 0, 'f', 1)
                        .arg(checksumFull == expected ? "(magic incl)" : "(magic excl)");
                    qWarning().noquote() << pktMsg;
                    emit logReceived(pktMsg);
                }
            } else {
                m_checksumFails++;
                if (m_checksumFails <= 5) {
                    QString failMsg = QString("CHECKSUM FAIL #%1 expected:%2 full:%3 noMagic:%4")
                        .arg(m_checksumFails)
                        .arg(expected, 2, 16, QChar('0'))
                        .arg(checksumFull, 2, 16, QChar('0'))
                        .arg(checksumNoMagic, 2, 16, QChar('0'));
                    qWarning().noquote() << failMsg;
                    emit logReceived(failMsg);
                }
                m_buffer = m_buffer.mid(1);  // 1바이트 건너뛰고 재동기
            }
            continue;
        }

        // ── Case 3: 매직도 \n도 없음 → 데이터 부족, 대기 ──
        break;
    }
}

/**
 * parseTelemetryPacket()
 *
 * 110바이트 바이너리 패킷을 파싱하여 m_telemetry 구조체에 저장.
 * Little-endian, memcpy 기반.
 *
 * 패킷 레이아웃 (매뉴얼 §2.2):
 *   0:  magic (0xAA 0x55)
 *   2:  uint32  timestamp_ms
 *   6:  float×3 roll, pitch, yaw
 *  18:  float×3 gyroX, gyroY, gyroZ
 *  30:  float×2 accelX, accelY
 *  38:  int32   targetRPM
 *  42:  int32×2 wheel1_rpm, wheel2_rpm
 *  50:  float×2 wheel1_pwm, wheel2_pwm
 *  58:  uint8   wheel_state
 *  59:  float×3 gimbal_angle, gimbal_target, gimbal_velocity
 *  71:  float×2 gimbal1, gimbal2
 *  79:  uint8   balancing
 *  80:  float×4 balKp, balKi, balKd, washout
 *  96:  float×3 wheelKp, wheelKi, wheelKd
 * 108:  uint8   comm_bits
 * 109:  uint8   checksum
 */
void CMGSerialManager::parseTelemetryPacket(const QByteArray &pkt)
{
    const char *d = pkt.constData();

    std::memcpy(&m_telemetry.timestampMs, d + 2,  4);

    std::memcpy(&m_telemetry.roll,  d + 6,  4);
    std::memcpy(&m_telemetry.pitch, d + 10, 4);
    std::memcpy(&m_telemetry.yaw,   d + 14, 4);

    std::memcpy(&m_telemetry.gyroX, d + 18, 4);
    std::memcpy(&m_telemetry.gyroY, d + 22, 4);
    std::memcpy(&m_telemetry.gyroZ, d + 26, 4);

    std::memcpy(&m_telemetry.accelX, d + 30, 4);
    std::memcpy(&m_telemetry.accelY, d + 34, 4);

    std::memcpy(&m_telemetry.targetRPM,  d + 38, 4);
    std::memcpy(&m_telemetry.wheel1Rpm,  d + 42, 4);
    std::memcpy(&m_telemetry.wheel2Rpm,  d + 46, 4);
    std::memcpy(&m_telemetry.wheel1Pwm,  d + 50, 4);
    std::memcpy(&m_telemetry.wheel2Pwm,  d + 54, 4);

    m_telemetry.wheelState = static_cast<quint8>(d[58]);

    std::memcpy(&m_telemetry.gimbalAngle,    d + 59, 4);
    std::memcpy(&m_telemetry.gimbalTarget,   d + 63, 4);
    std::memcpy(&m_telemetry.gimbalVelocity, d + 67, 4);

    std::memcpy(&m_telemetry.gimbal1, d + 71, 4);
    std::memcpy(&m_telemetry.gimbal2, d + 75, 4);

    m_telemetry.balancing = static_cast<quint8>(d[79]);

    std::memcpy(&m_telemetry.balKp,   d + 80, 4);
    std::memcpy(&m_telemetry.balKi,   d + 84, 4);
    std::memcpy(&m_telemetry.balKd,   d + 88, 4);
    std::memcpy(&m_telemetry.washout, d + 92, 4);

    std::memcpy(&m_telemetry.wheelKp, d + 96,  4);
    std::memcpy(&m_telemetry.wheelKi, d + 100, 4);
    std::memcpy(&m_telemetry.wheelKd, d + 104, 4);

    m_telemetry.commBits = static_cast<quint8>(d[108]);

    // CSV 녹화: 매 패킷마다 기록
    if (m_recording && m_csvStream) {
        quint32 elapsed = m_telemetry.timestampMs - m_recordStartTs;
        int mins = (elapsed / 60000) % 100;
        int secs = (elapsed / 1000) % 60;
        int ms   = elapsed % 1000;
        QString timeStr = QString("%1:%2.%3")
            .arg(mins, 2, 10, QChar('0'))
            .arg(secs, 2, 10, QChar('0'))
            .arg(ms, 3, 10, QChar('0'));
        double torque = (m_telemetry.wheel1Rpm / 1000.0) * m_telemetry.gimbalVelocity;
        *m_csvStream << timeStr << ","
                     << m_telemetry.timestampMs << ","
                     << QString::number(m_telemetry.roll, 'f', 4) << ","
                     << QString::number(m_telemetry.gyroX, 'f', 4) << ","
                     << QString::number(m_telemetry.gimbalAngle, 'f', 4) << ","
                     << QString::number(m_telemetry.gimbalVelocity, 'f', 4) << ","
                     << QString::number(torque, 'f', 4) << ","
                     << m_telemetry.wheel1Rpm << ","
                     << m_telemetry.wheel2Rpm << "\n";
    }

    emit telemetryUpdated();
}

void CMGSerialManager::processAsciiLine(const QString &line)
{
    if (line.isEmpty())
        return;

    if (line.startsWith("STATUS:"))
        emit statusReceived(line);

    emit logReceived(line);
}

// ═══════════════════════════════════════════════
// Property Getters
// ═══════════════════════════════════════════════

double CMGSerialManager::roll()   const { return m_telemetry.roll; }
double CMGSerialManager::pitch()  const { return m_telemetry.pitch; }
double CMGSerialManager::yaw()    const { return m_telemetry.yaw; }
double CMGSerialManager::gyroX()  const { return m_telemetry.gyroX; }
double CMGSerialManager::gyroY()  const { return m_telemetry.gyroY; }
double CMGSerialManager::gyroZ()  const { return m_telemetry.gyroZ; }
double CMGSerialManager::accelX() const { return m_telemetry.accelX; }
double CMGSerialManager::accelY() const { return m_telemetry.accelY; }

int    CMGSerialManager::targetRPM()  const { return m_telemetry.targetRPM; }
int    CMGSerialManager::wheel1Rpm()  const { return m_telemetry.wheel1Rpm; }
int    CMGSerialManager::wheel2Rpm()  const { return m_telemetry.wheel2Rpm; }
double CMGSerialManager::wheel1Pwm()  const { return m_telemetry.wheel1Pwm; }
double CMGSerialManager::wheel2Pwm()  const { return m_telemetry.wheel2Pwm; }
int    CMGSerialManager::wheelState() const { return m_telemetry.wheelState; }

double CMGSerialManager::gimbalAngle()    const { return m_telemetry.gimbalAngle; }
double CMGSerialManager::gimbalTarget()   const { return m_telemetry.gimbalTarget; }
double CMGSerialManager::gimbalVelocity() const { return m_telemetry.gimbalVelocity; }

bool   CMGSerialManager::balancing() const { return m_telemetry.balancing != 0; }
double CMGSerialManager::balKp()     const { return m_telemetry.balKp; }
double CMGSerialManager::balKi()     const { return m_telemetry.balKi; }
double CMGSerialManager::balKd()     const { return m_telemetry.balKd; }
double CMGSerialManager::washout()   const { return m_telemetry.washout; }

double CMGSerialManager::wheelKp() const { return m_telemetry.wheelKp; }
double CMGSerialManager::wheelKi() const { return m_telemetry.wheelKi; }
double CMGSerialManager::wheelKd() const { return m_telemetry.wheelKd; }

int     CMGSerialManager::commBits()    const { return m_telemetry.commBits; }
quint32 CMGSerialManager::timestampMs() const { return m_telemetry.timestampMs; }
int     CMGSerialManager::packetCount() const { return m_packetCount; }

// ═══════════════════════════════════════════════
// CSV Recording
// ═══════════════════════════════════════════════

void CMGSerialManager::startRecording(const QString &folderPath)
{
    if (m_recording)
        stopRecording();

    QDir dir;
    if (!dir.exists(folderPath))
        dir.mkpath(folderPath);

    QString fileName = QDateTime::currentDateTime().toString("yyyy-MM-dd_hhmmss") + ".csv";
    QString filePath = folderPath + "/" + fileName;

    m_csvFile = new QFile(filePath, this);
    if (m_csvFile->open(QIODevice::WriteOnly | QIODevice::Text)) {
        m_csvStream = new QTextStream(m_csvFile);
        *m_csvStream << "time,timestamp_ms,roll_angle,roll_velocity,gimbal_angle,gimbal_velocity,torque,wheel_rpm1,wheel_rpm2\n";
        m_csvStream->flush();
        m_recording = true;
        m_recordStartTs = m_telemetry.timestampMs;
        qWarning() << "CMGSerialManager: Recording started -" << filePath;
        emit logReceived("Recording: " + filePath);
    } else {
        qWarning() << "CMGSerialManager: Failed to create CSV -" << filePath;
        emit logReceived("Recording failed: " + filePath);
        delete m_csvFile;
        m_csvFile = nullptr;
    }
}

void CMGSerialManager::stopRecording()
{
    if (!m_recording)
        return;

    m_recording = false;
    if (m_csvStream) {
        m_csvStream->flush();
        delete m_csvStream;
        m_csvStream = nullptr;
    }
    if (m_csvFile) {
        m_csvFile->close();
        qWarning() << "CMGSerialManager: Recording stopped -" << m_csvFile->fileName();
        emit logReceived("Recording stopped: " + m_csvFile->fileName());
        delete m_csvFile;
        m_csvFile = nullptr;
    }
}

bool CMGSerialManager::isRecording() const
{
    return m_recording;
}

// ═══════════════════════════════════════════════
// Auto-Reconnect
// ═══════════════════════════════════════════════

void CMGSerialManager::startReconnectTimer()
{
    if (m_autoReconnect && !m_reconnectTimer->isActive()) {
        qWarning() << "CMGSerialManager: Reconnect timer started (every"
                   << m_reconnectTimer->interval() << "ms)";
        m_reconnectTimer->start();
    }
}

void CMGSerialManager::stopReconnectTimer()
{
    if (m_reconnectTimer->isActive()) {
        m_reconnectTimer->stop();
        qWarning() << "CMGSerialManager: Reconnect timer stopped";
    }
}

void CMGSerialManager::tryReconnect()
{
    if (!m_autoReconnect) {
        stopReconnectTimer();
        return;
    }

    // 이미 연결되어 있으면 중단
    if (m_serial->isOpen()) {
        stopReconnectTimer();
        return;
    }

    // 포트 목록 갱신
    refreshPorts();

    if (m_ports.isEmpty()) {
        qDebug() << "CMGSerialManager: No ports available, retrying...";
        return;   // 타이머 계속 → 다음 주기에 재시도
    }

    // 1순위: 마지막으로 연결했던 포트
    QString targetPort;
    if (!m_lastPortName.isEmpty() && m_ports.contains(m_lastPortName)) {
        targetPort = m_lastPortName;
    } else {
        // 2순위: 사용 가능한 마지막 포트 (보통 가장 최근 장치)
        targetPort = m_ports.last();
    }

    qWarning() << "CMGSerialManager: Trying reconnect to" << targetPort << "@" << m_lastBaudRate;

    m_serial->setPortName(targetPort);
    m_serial->setBaudRate(m_lastBaudRate);
    m_serial->setDataBits(QSerialPort::Data8);
    m_serial->setParity(QSerialPort::NoParity);
    m_serial->setStopBits(QSerialPort::OneStop);
    m_serial->setFlowControl(QSerialPort::NoFlowControl);

    if (m_serial->open(QIODevice::ReadWrite)) {
        m_serial->clear();
        stopReconnectTimer();
        m_lastPortName = targetPort;
        m_buffer.clear();
        m_asciiCarry.clear();
        m_packetCount = 0;
        m_checksumFails = 0;
        m_totalBytesReceived = 0;
        m_dataReceived = false;
        qWarning() << "CMGSerialManager: Port reopened:" << targetPort << "@" << m_lastBaudRate;
        setConnectionStatus("Connecting: " + targetPort + " @ " + QString::number(m_lastBaudRate));
        emit logReceived("Connecting: " + targetPort + " @ " + QString::number(m_lastBaudRate));
        m_dataTimeoutTimer->start();
    } else {
        qDebug() << "CMGSerialManager: Reconnect failed -" << m_serial->errorString();
        // 타이머 계속 → 다음 주기에 재시도
    }
}
