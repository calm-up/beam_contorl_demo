#pragma once

#include <QString>
#include <vector>

// 为后续自动校准预留的边界。当前版本不实例化或连接外部仪器。
struct Measurement {
    double frequencyGHz = 0;
    double magnitudeDb = 0;
    double phaseDegrees = 0;
};

class MeasurementInstrument {
public:
    virtual ~MeasurementInstrument() = default;
    virtual bool connectTo(const QString &address, QString &error) = 0;
    virtual bool setFrequencyGHz(double frequency, QString &error) = 0;
    virtual bool acquire(Measurement &result, QString &error) = 0;
    virtual void disconnect() = 0;
};

class MotionStage {
public:
    virtual ~MotionStage() = default;
    virtual bool connectTo(const QString &address, QString &error) = 0;
    virtual bool moveDegrees(double azimuth, double elevation, QString &error) = 0;
    virtual bool stop(QString &error) = 0;
    virtual void disconnect() = 0;
};
