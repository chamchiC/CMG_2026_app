#ifndef FILELOGGER_H
#define FILELOGGER_H

#include <QObject>
#include <QFile>
#include <QTextStream>
#include <QMap>
#include <QDir>
#include <QDateTime>
#include <QCoreApplication>

class FileLogger : public QObject
{
    Q_OBJECT

public:
    explicit FileLogger(QObject *parent = nullptr);
    ~FileLogger();

    Q_INVOKABLE void startSession();
    Q_INVOKABLE void appendData(const QString &channel, double time, double value);
    Q_INVOKABLE void endSession();
    Q_INVOKABLE QString logFolderPath() const;

private:
    QMap<QString, QFile*> m_files;
    QMap<QString, QTextStream*> m_streams;
    QString m_sessionTimestamp;
    QString m_logDir;
    bool m_active;

    void closeAll();
};

#endif // FILELOGGER_H
