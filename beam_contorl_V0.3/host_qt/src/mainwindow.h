#pragma once

#include "protocol.h"

#include <QMainWindow>
#include <QJsonArray>
#include <QPointer>
#include <QQueue>
#include <QVector>
#include <optional>

class QComboBox;
class QLabel;
class QLineEdit;
class QPushButton;
class QSerialPort;
class QSpinBox;
class QStackedWidget;
class QTableWidget;
class QTimer;
class QTreeWidget;
class QFormLayout;

class MainWindow : public QMainWindow {
public:
    explicit MainWindow(QWidget *parent = nullptr);
    ~MainWindow() override;

private:
    struct ChannelState {
        bool enable = false;
        int phase = 0;
        int attenuation = 0;
        QString result = QStringLiteral("未知");
    };
    struct Job {
        beam::Frame frame;
        QString description;
        int channelRow = -1;
        int channelArray = -1;
        int channelLine = -1;
    };

    QComboBox *transportBox_ = nullptr;
    QComboBox *portBox_ = nullptr;
    QComboBox *arrayBox_ = nullptr;
    QComboBox *simulateBox_ = nullptr;
    QPushButton *connectButton_ = nullptr;
    QLabel *connectionLabel_ = nullptr;
    QTreeWidget *navigation_ = nullptr;
    QStackedWidget *pages_ = nullptr;
    QTableWidget *channels_ = nullptr;
    QTableWidget *log_ = nullptr;
    QSpinBox *lineBox_ = nullptr;
    QSpinBox *phaseBox_ = nullptr;
    QSpinBox *attenBox_ = nullptr;
    QComboBox *enableBox_ = nullptr;
    QLabel *physicalLabel_ = nullptr;
    QLabel *modeLabel_ = nullptr;
    QLabel *resultLabel_ = nullptr;
    QLineEdit *preview_ = nullptr;
    QFormLayout *fieldsLayout_ = nullptr;
    QWidget *fieldsHolder_ = nullptr;
    QPushButton *sendButton_ = nullptr;
    QPushButton *batchButton_ = nullptr;
    QPushButton *applyButton_ = nullptr;
    QPushButton *stopButton_ = nullptr;
    QSerialPort *port_ = nullptr;
    QTimer *timeout_ = nullptr;

    QVector<QSpinBox *> fieldEditors_;
    QVector<ChannelState> channelStates_ = QVector<ChannelState>(256);
    QQueue<Job> queue_;
    std::optional<Job> active_;
    beam::FrameStream incoming_;
    int modeIndex_ = 1;
    bool connected_ = false;
    bool uncertain_ = false;
    bool loadingTable_ = false;

    void setupUi();
    QWidget *buildChannelPage();
    QWidget *buildCommandPage();
    void refreshPorts();
    void toggleConnection();
    void selectMode(int index);
    void updateCommandForm();
    void updatePreview();
    void updateChannelTable();
    void updateChannelEditor();
    void applyChannelEditor();
    void sendCurrent();
    void sendChecked();
    void enqueue(Job job);
    void startNext();
    void receiveBytes(const uint8_t *data, size_t size);
    void handleResponse(const beam::Frame &frame);
    void markTimeout();
    void logEntry(const QString &direction, const QString &message, const QString &bytes = {});
    void saveConfiguration();
    void loadConfiguration();
    void exportLog();
    void updateControls();
    beam::Frame currentFrame() const;
    Job channelJob(int row) const;
    int stateIndex(int array, int line, int row) const { return array * 128 + line * 16 + row; }
};
