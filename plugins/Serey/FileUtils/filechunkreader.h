#pragma once

#include <QObject>
#include <QByteArray>
#include <QUrl>

// Reads a local file in slices so QML can upload large videos with constant
// memory (whole-file XMLHttpRequest reads OOM-crashed phones). Offsets/sizes
// are exposed as double: JS numbers are exact up to 2^53, beyond any video size.
class FileChunkReader : public QObject
{
    Q_OBJECT

public:
    explicit FileChunkReader(QObject *parent = nullptr);

    // File size in bytes, or -1 if the file can't be opened.
    Q_INVOKABLE double size(const QUrl &fileUrl) const;

    // Up to maxBytes starting at offset. Empty on error or EOF.
    // QByteArray surfaces in QML JS as an ArrayBuffer, xhr.send()-able as-is.
    Q_INVOKABLE QByteArray read(const QUrl &fileUrl, double offset, double maxBytes) const;

private:
    static QString localPath(const QUrl &fileUrl);
};
