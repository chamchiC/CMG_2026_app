#include "filelogger.h"
#include <QDebug>

FileLogger::FileLogger(QObject *parent)
    : QObject(parent)
    , m_active(false)
{
}

FileLogger::~FileLogger()
{
    closeAll();
}

void FileLogger::startSession()
{
    if (m_active)
        closeAll();

    m_logDir = QCoreApplication::applicationDirPath() + "/logs";
    QDir dir;
    if (!dir.exists(m_logDir))
        dir.mkpath(m_logDir);

    m_sessionTimestamp = QDateTime::currentDateTime().toString("yyyy-MM-dd_hhmmss");

    QStringList channels = {"RollAngle", "GimbalAngle", "RollVelocity", "GimbalVelocity", "Torque"};

    for (const QString &ch : channels) {
        QString filePath = m_logDir + "/" + m_sessionTimestamp + "_" + ch + ".txt";
        QFile *file = new QFile(filePath, this);

        if (file->open(QIODevice::WriteOnly | QIODevice::Text)) {
            QTextStream *stream = new QTextStream(file);
            *stream << "Time(s)\tValue\n";
            stream->flush();

            m_files[ch] = file;
            m_streams[ch] = stream;
        } else {
            qWarning() << "FileLogger: Could not open file:" << filePath;
            delete file;
        }
    }

    m_active = true;
    qDebug() << "FileLogger: Session started -" << m_sessionTimestamp;
}

void FileLogger::appendData(const QString &channel, double time, double value)
{
    if (!m_active)
        return;

    if (m_streams.contains(channel)) {
        QTextStream *stream = m_streams[channel];
        *stream << QString::number(time, 'f', 1) << "\t" << QString::number(value, 'f', 4) << "\n";
        stream->flush();
    }
}

void FileLogger::endSession()
{
    if (!m_active)
        return;

    closeAll();
    qDebug() << "FileLogger: Session ended -" << m_sessionTimestamp;
}

QString FileLogger::logFolderPath() const
{
    return m_logDir;
}

void FileLogger::closeAll()
{
    qDeleteAll(m_streams);
    m_streams.clear();

    for (QFile *file : m_files) {
        if (file->isOpen())
            file->close();
        delete file;
    }
    m_files.clear();

    m_active = false;
}
