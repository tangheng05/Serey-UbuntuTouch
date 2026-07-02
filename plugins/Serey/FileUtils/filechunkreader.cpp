#include "filechunkreader.h"

#include <QFile>
#include <QFileInfo>

FileChunkReader::FileChunkReader(QObject *parent)
    : QObject(parent)
{
}

QString FileChunkReader::localPath(const QUrl &fileUrl)
{
    if (fileUrl.isLocalFile())
        return fileUrl.toLocalFile();
    // Tolerate bare paths passed as strings ("/home/phablet/...").
    if (fileUrl.scheme().isEmpty())
        return fileUrl.toString();
    return QString();
}

double FileChunkReader::size(const QUrl &fileUrl) const
{
    const QString path = localPath(fileUrl);
    if (path.isEmpty())
        return -1;
    QFileInfo info(path);
    if (!info.exists() || !info.isFile())
        return -1;
    return static_cast<double>(info.size());
}

QByteArray FileChunkReader::read(const QUrl &fileUrl, double offset, double maxBytes) const
{
    const QString path = localPath(fileUrl);
    if (path.isEmpty() || offset < 0 || maxBytes <= 0)
        return QByteArray();

    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return QByteArray();
    if (!file.seek(static_cast<qint64>(offset)))
        return QByteArray();

    return file.read(static_cast<qint64>(maxBytes));
}
