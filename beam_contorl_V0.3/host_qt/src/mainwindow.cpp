#include "mainwindow.h"

#include <QAbstractItemView>
#include <QCheckBox>
#include <QComboBox>
#include <QDateTime>
#include <QFile>
#include <QFileDialog>
#include <QFormLayout>
#include <QGroupBox>
#include <QHeaderView>
#include <QHBoxLayout>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLabel>
#include <QLineEdit>
#include <QMessageBox>
#include <QPushButton>
#include <QSerialPort>
#include <QSerialPortInfo>
#include <QScrollArea>
#include <QSignalBlocker>
#include <QSpinBox>
#include <QStackedWidget>
#include <QSplitter>
#include <QStatusBar>
#include <QTableWidget>
#include <QTextStream>
#include <QTimer>
#include <QTreeWidget>
#include <QVBoxLayout>

#include <algorithm>
#include <stdexcept>

namespace {
QString zh(const char *value) { return QString::fromUtf8(value); }
QString bytesText(const std::vector<uint8_t> &bytes) { return QString::fromStdString(beam::hex(bytes)); }
QString statusName(uint8_t status) {
    static const char *names[] = {"成功", "校验错误", "长度或版本错误", "参数越界", "忙",
                                  "命令或字段不支持", "硬件或读回失败", "缺少数据", "写保护或目标不安全"};
    return status < 9 ? zh(names[status]) : QStringLiteral("未知状态 0x%1").arg(status, 2, 16, QChar('0'));
}
QSpinBox *spin(int min, int max, int value, bool hex = false) {
    auto *widget = new QSpinBox;
    widget->setRange(min, max);
    widget->setValue(value);
    if (hex) { widget->setDisplayIntegerBase(16); widget->setPrefix("0x"); }
    widget->setMinimumWidth(110);
    return widget;
}
}

MainWindow::MainWindow(QWidget *parent) : QMainWindow(parent) {
    port_ = new QSerialPort(this);
    timeout_ = new QTimer(this);
    timeout_->setSingleShot(true);
    setupUi();
    connect(timeout_, &QTimer::timeout, this, [this] { markTimeout(); });
    connect(port_, &QSerialPort::readyRead, this, [this] {
        QByteArray data = port_->readAll();
        logEntry(QStringLiteral("接收"), QStringLiteral("串口数据"),
                 bytesText({reinterpret_cast<const uint8_t *>(data.constData()),
                            reinterpret_cast<const uint8_t *>(data.constData()) + data.size()}));
        receiveBytes(reinterpret_cast<const uint8_t *>(data.constData()), static_cast<size_t>(data.size()));
    });
    connect(port_, &QSerialPort::errorOccurred, this, [this](QSerialPort::SerialPortError error) {
        if (error == QSerialPort::NoError) return;
        logEntry(QStringLiteral("错误"), port_->errorString());
        if (error == QSerialPort::ResourceError) {
            port_->close(); connected_ = false; uncertain_ = true;
            queue_.clear(); active_.reset(); timeout_->stop(); updateControls();
        }
    });
    refreshPorts();
    navigation_->setCurrentItem(navigation_->topLevelItem(0)->child(1));
    updateControls();
}

MainWindow::~MainWindow() = default;

void MainWindow::setupUi() {
    setWindowTitle(QStringLiteral("阵列波控调试工具 · V0.3"));
    resize(1500, 950);
    setMinimumSize(1050, 690);
    auto *root = new QWidget;
    auto *layout = new QVBoxLayout(root);
    layout->setContentsMargins(16, 14, 16, 12);
    layout->setSpacing(10);

    auto *bar = new QHBoxLayout;
    auto *title = new QLabel(QStringLiteral("阵列波控调试工具"));
    title->setObjectName("title");
    bar->addWidget(title);
    bar->addSpacing(14);
    bar->addWidget(new QLabel(QStringLiteral("协议 V0.3")));
    bar->addStretch();
    transportBox_ = new QComboBox;
    transportBox_->addItems({QStringLiteral("模拟设备"), QStringLiteral("RS422串口")});
    bar->addWidget(transportBox_);
    portBox_ = new QComboBox;
    portBox_->setMinimumWidth(130);
    bar->addWidget(portBox_);
    auto *refreshButton = new QPushButton(QStringLiteral("刷新串口"));
    bar->addWidget(refreshButton);
    simulateBox_ = new QComboBox;
    simulateBox_->setObjectName("simulateBehavior");
    simulateBox_->addItems({QStringLiteral("模拟：成功"), QStringLiteral("模拟：忙"),
                            QStringLiteral("模拟：参数越界"), QStringLiteral("模拟：分段回包"),
                            QStringLiteral("模拟：错误校验"), QStringLiteral("模拟：无应答")});
    bar->addWidget(simulateBox_);
    connectButton_ = new QPushButton(QStringLiteral("连接"));
    connectButton_->setObjectName("connectButton");
    connectButton_->setProperty("primary", true);
    bar->addWidget(connectButton_);
    connectionLabel_ = new QLabel;
    bar->addWidget(connectionLabel_);
    layout->addLayout(bar);

    auto *scope = new QHBoxLayout;
    scope->addWidget(new QLabel(QStringLiteral("操作阵面")));
    arrayBox_ = new QComboBox;
    arrayBox_->addItem(QStringLiteral("接收阵面"), 0);
    arrayBox_->addItem(QStringLiteral("发射阵面"), 1);
    arrayBox_->addItem(QStringLiteral("双阵面（仅适用命令）"), 2);
    arrayBox_->addItem(QStringLiteral("全局查询"), 0xFF);
    scope->addWidget(arrayBox_);
    scope->addSpacing(14);
    scope->addWidget(new QLabel(QStringLiteral("使用位置：接收阵面 J1；索引0～3对应SDI1～4")));
    scope->addStretch();
    auto *saveButton = new QPushButton(QStringLiteral("保存通道配置"));
    auto *loadButton = new QPushButton(QStringLiteral("载入通道配置"));
    scope->addWidget(saveButton);
    scope->addWidget(loadButton);
    layout->addLayout(scope);

    auto *main = new QSplitter(Qt::Horizontal);
    navigation_ = new QTreeWidget;
    navigation_->setHeaderHidden(true);
    navigation_->setMinimumWidth(190);
    navigation_->setMaximumWidth(260);
    QTreeWidgetItem *group = nullptr;
    QString currentGroup;
    for (size_t i = 0; i < beam::modes().size(); ++i) {
        const auto &mode = beam::modes()[i];
        if (currentGroup != zh(mode.group)) {
            currentGroup = zh(mode.group);
            group = new QTreeWidgetItem(navigation_, {currentGroup});
            group->setFlags(group->flags() & ~Qt::ItemIsSelectable);
        }
        auto *item = new QTreeWidgetItem(group, {zh(mode.name)});
        item->setData(0, Qt::UserRole, static_cast<int>(i));
    }
    navigation_->expandAll();
    main->addWidget(navigation_);

    pages_ = new QStackedWidget;
    pages_->addWidget(buildChannelPage());
    pages_->addWidget(buildCommandPage());
    main->addWidget(pages_);

    auto *detail = new QGroupBox(QStringLiteral("命令详情"));
    detail->setMinimumWidth(300);
    auto *detailLayout = new QVBoxLayout(detail);
    modeLabel_ = new QLabel;
    modeLabel_->setWordWrap(true);
    detailLayout->addWidget(modeLabel_);
    detailLayout->addWidget(new QLabel(QStringLiteral("完整报文（原始十六进制字节）")));
    preview_ = new QLineEdit;
    preview_->setReadOnly(true);
    preview_->setObjectName("framePreview");
    preview_->setToolTip(QStringLiteral("此处为字节预览；串口发送时不发送空格字符"));
    detailLayout->addWidget(preview_);
    resultLabel_ = new QLabel(QStringLiteral("板端状态：未知"));
    resultLabel_->setObjectName("resultLabel");
    resultLabel_->setWordWrap(true);
    detailLayout->addWidget(resultLabel_);
    detailLayout->addWidget(new QLabel(QStringLiteral("状态含义：已发送仅代表电脑写入串口；成功须以应答为准。")));
    auto *buttons = new QHBoxLayout;
    sendButton_ = new QPushButton(QStringLiteral("发送当前命令"));
    sendButton_->setObjectName("sendButton");
    sendButton_->setProperty("primary", true);
    stopButton_ = new QPushButton(QStringLiteral("停止后续任务"));
    buttons->addWidget(sendButton_);
    buttons->addWidget(stopButton_);
    detailLayout->addLayout(buttons);
    detailLayout->addStretch();
    main->addWidget(detail);
    main->setStretchFactor(0, 0);
    main->setStretchFactor(1, 4);
    main->setStretchFactor(2, 2);
    layout->addWidget(main, 3);

    auto *logTitle = new QHBoxLayout;
    logTitle->addWidget(new QLabel(QStringLiteral("通信与任务日志")));
    logTitle->addStretch();
    auto *clearButton = new QPushButton(QStringLiteral("清空显示"));
    auto *exportButton = new QPushButton(QStringLiteral("导出日志"));
    logTitle->addWidget(exportButton);
    logTitle->addWidget(clearButton);
    layout->addLayout(logTitle);
    log_ = new QTableWidget(0, 4);
    log_->setObjectName("communicationLog");
    log_->setHorizontalHeaderLabels({QStringLiteral("时间"), QStringLiteral("方向"),
                                      QStringLiteral("说明"), QStringLiteral("字节")});
    log_->setEditTriggers(QAbstractItemView::NoEditTriggers);
    log_->setSelectionBehavior(QAbstractItemView::SelectRows);
    log_->verticalHeader()->hide();
    log_->horizontalHeader()->setSectionResizeMode(0, QHeaderView::ResizeToContents);
    log_->horizontalHeader()->setSectionResizeMode(1, QHeaderView::ResizeToContents);
    log_->horizontalHeader()->setSectionResizeMode(2, QHeaderView::Stretch);
    log_->horizontalHeader()->setSectionResizeMode(3, QHeaderView::Stretch);
    layout->addWidget(log_, 1);
    setCentralWidget(root);

    setStyleSheet(R"(
        QMainWindow, QWidget { background: #f5f7fa; color: #253044; }
        QLabel#title { font-size: 20px; font-weight: 700; color: #1d3555; }
        QGroupBox { border: 1px solid #d9e1eb; border-radius: 6px; margin-top: 12px;
                    padding: 10px; background: white; font-weight: 600; }
        QGroupBox::title { subcontrol-origin: margin; left: 12px; padding: 0 4px; }
        QPushButton { background: white; border: 1px solid #cad4e1; border-radius: 5px;
                      min-height: 30px; padding: 2px 10px; }
        QPushButton:hover { border-color: #4781bd; }
        QPushButton[primary="true"] { background: #276da8; border-color: #276da8; color: white; }
        QTreeWidget, QTableWidget, QLineEdit, QSpinBox, QComboBox {
            background: white; border: 1px solid #d2dae5; border-radius: 4px; }
        QHeaderView::section { background: #eaf0f7; border: 0; border-bottom: 1px solid #d2dae5;
                               padding: 6px; font-weight: 600; }
    )");

    connect(refreshButton, &QPushButton::clicked, this, [this] { refreshPorts(); });
    connect(connectButton_, &QPushButton::clicked, this, [this] { toggleConnection(); });
    connect(transportBox_, qOverload<int>(&QComboBox::currentIndexChanged), this,
            [this] { if (connected_) toggleConnection(); updateControls(); });
    connect(navigation_, &QTreeWidget::currentItemChanged, this,
            [this](QTreeWidgetItem *item) {
                if (item && item->data(0, Qt::UserRole).isValid())
                    selectMode(item->data(0, Qt::UserRole).toInt());
            });
    connect(arrayBox_, qOverload<int>(&QComboBox::currentIndexChanged), this,
            [this] { updateChannelTable(); updatePreview(); });
    connect(sendButton_, &QPushButton::clicked, this, [this] { sendCurrent(); });
    connect(stopButton_, &QPushButton::clicked, this, [this] {
        queue_.clear(); logEntry(QStringLiteral("任务"), QStringLiteral("已停止后续任务；正在等待的命令继续等待结果"));
        updateControls();
    });
    connect(saveButton, &QPushButton::clicked, this, [this] { saveConfiguration(); });
    connect(loadButton, &QPushButton::clicked, this, [this] { loadConfiguration(); });
    connect(clearButton, &QPushButton::clicked, this, [this] { log_->setRowCount(0); });
    connect(exportButton, &QPushButton::clicked, this, [this] { exportLog(); });
}

QWidget *MainWindow::buildChannelPage() {
    auto *page = new QWidget;
    auto *layout = new QVBoxLayout(page);
    auto *top = new QHBoxLayout;
    top->addWidget(new QLabel(QStringLiteral("线阵编号")));
    lineBox_ = spin(0, 7, 0);
    top->addWidget(lineBox_);
    top->addWidget(new QLabel(QStringLiteral("每条线阵：4颗芯片 × 4通道")));
    top->addStretch();
    layout->addLayout(top);
    channels_ = new QTableWidget(16, 7);
    channels_->setHorizontalHeaderLabels({QStringLiteral("批量"), QStringLiteral("芯片"),
        QStringLiteral("通道"), QStringLiteral("开关"), QStringLiteral("移相码"),
        QStringLiteral("衰减码"), QStringLiteral("结果")});
    channels_->setSelectionBehavior(QAbstractItemView::SelectRows);
    channels_->setSelectionMode(QAbstractItemView::SingleSelection);
    channels_->verticalHeader()->hide();
    channels_->horizontalHeader()->setSectionResizeMode(QHeaderView::Stretch);
    layout->addWidget(channels_, 1);
    auto *editor = new QGroupBox(QStringLiteral("选中通道参数"));
    auto *row = new QHBoxLayout(editor);
    row->addWidget(new QLabel(QStringLiteral("使能")));
    enableBox_ = new QComboBox;
    enableBox_->addItems({QStringLiteral("关闭"), QStringLiteral("打开")});
    row->addWidget(enableBox_);
    row->addWidget(new QLabel(QStringLiteral("移相码")));
    phaseBox_ = spin(0, 63, 0);
    row->addWidget(phaseBox_);
    row->addWidget(new QLabel(QStringLiteral("衰减码")));
    attenBox_ = spin(0, 63, 0);
    row->addWidget(attenBox_);
    physicalLabel_ = new QLabel;
    row->addWidget(physicalLabel_);
    row->addStretch();
    applyButton_ = new QPushButton(QStringLiteral("应用到选中行"));
    batchButton_ = new QPushButton(QStringLiteral("发送勾选通道"));
    row->addWidget(applyButton_);
    row->addWidget(batchButton_);
    layout->addWidget(editor);
    connect(lineBox_, qOverload<int>(&QSpinBox::valueChanged), this,
            [this] { updateChannelTable(); updatePreview(); });
    connect(channels_, &QTableWidget::itemSelectionChanged, this,
            [this] { updateChannelEditor(); updatePreview(); });
    connect(phaseBox_, qOverload<int>(&QSpinBox::valueChanged), this,
            [this] { updatePreview(); });
    connect(attenBox_, qOverload<int>(&QSpinBox::valueChanged), this,
            [this] { updatePreview(); });
    connect(enableBox_, qOverload<int>(&QComboBox::currentIndexChanged), this,
            [this] { updatePreview(); });
    connect(applyButton_, &QPushButton::clicked, this, [this] { applyChannelEditor(); });
    connect(batchButton_, &QPushButton::clicked, this, [this] { sendChecked(); });
    updateChannelTable();
    return page;
}

QWidget *MainWindow::buildCommandPage() {
    auto *page = new QWidget;
    auto *layout = new QVBoxLayout(page);
    auto *hint = new QLabel(QStringLiteral("字段以十六进制字节输入。高、低字节按表中顺序填写；发送前可在右侧核对完整报文。"));
    hint->setWordWrap(true);
    layout->addWidget(hint);
    auto *scroll = new QScrollArea;
    scroll->setWidgetResizable(true);
    fieldsHolder_ = new QWidget;
    fieldsLayout_ = new QFormLayout(fieldsHolder_);
    fieldsLayout_->setSpacing(8);
    fieldsLayout_->setFieldGrowthPolicy(QFormLayout::FieldsStayAtSizeHint);
    scroll->setWidget(fieldsHolder_);
    layout->addWidget(scroll, 1);
    return page;
}

void MainWindow::refreshPorts() {
    const QString old = portBox_->currentData().toString();
    portBox_->clear();
    for (const auto &info : QSerialPortInfo::availablePorts())
        portBox_->addItem(info.portName() + QStringLiteral(" · ") + info.description(), info.portName());
    int index = portBox_->findData(old);
    if (index >= 0) portBox_->setCurrentIndex(index);
    updateControls();
}

void MainWindow::toggleConnection() {
    if (connected_) {
        timeout_->stop(); queue_.clear(); active_.reset(); incoming_.clear();
        port_->close(); connected_ = false; uncertain_ = false;
        logEntry(QStringLiteral("连接"), QStringLiteral("会话已断开；板端状态未确认"));
    } else {
        if (transportBox_->currentIndex() == 1) {
            if (portBox_->currentData().toString().isEmpty()) {
                QMessageBox::warning(this, QStringLiteral("无法连接"), QStringLiteral("请先选择串口")); return;
            }
            port_->setPortName(portBox_->currentData().toString());
            port_->setBaudRate(115200);
            port_->setDataBits(QSerialPort::Data8);
            port_->setParity(QSerialPort::NoParity);
            port_->setStopBits(QSerialPort::OneStop);
            port_->setFlowControl(QSerialPort::NoFlowControl);
            if (!port_->open(QIODevice::ReadWrite)) {
                QMessageBox::warning(this, QStringLiteral("串口连接失败"), port_->errorString()); return;
            }
            port_->clear(QSerialPort::AllDirections);
        }
        incoming_.clear(); uncertain_ = false; connected_ = true;
        logEntry(QStringLiteral("连接"), transportBox_->currentIndex() == 0
            ? QStringLiteral("模拟设备已连接")
            : QStringLiteral("RS422串口已连接：115200，8N1"));
    }
    updateControls();
}

void MainWindow::selectMode(int index) {
    if (index < 0 || static_cast<size_t>(index) >= beam::modes().size()) return;
    modeIndex_ = index;
    pages_->setCurrentIndex(index == 1 ? 0 : 1);
    modeLabel_->setText(QStringLiteral("当前命令：") + zh(beam::modes()[index].name));
    resultLabel_->setText(QStringLiteral("板端状态：未知"));
    updateCommandForm();
    updatePreview();
    updateControls();
}

void MainWindow::updateCommandForm() {
    while (fieldsLayout_->rowCount() > 0) fieldsLayout_->removeRow(0);
    fieldEditors_.clear();
    const auto &mode = beam::modes()[modeIndex_];
    for (const auto &field : mode.fields) {
        auto *editor = spin(field.minimum, field.maximum, field.initial, true);
        editor->setEnabled(!field.fixed);
        editor->setToolTip(zh(field.key));
        fieldsLayout_->addRow(zh(field.label), editor);
        fieldEditors_.push_back(editor);
        connect(editor, qOverload<int>(&QSpinBox::valueChanged), this,
                [this] { updatePreview(); });
    }
    if (mode.fields.empty()) fieldsLayout_->addRow(new QLabel(QStringLiteral("本命令没有数据区。")));
}

beam::Frame MainWindow::currentFrame() const {
    const auto &mode = beam::modes()[modeIndex_];
    beam::Frame frame{mode.command, static_cast<uint8_t>(arrayBox_->currentData().toInt()), {}};
    if (modeIndex_ == 1) {
        const int row = channels_->currentRow() < 0 ? 0 : channels_->currentRow();
        frame.payload = {static_cast<uint8_t>(lineBox_->value()), static_cast<uint8_t>(row / 4),
            static_cast<uint8_t>(row % 4), static_cast<uint8_t>(enableBox_->currentIndex()),
            static_cast<uint8_t>(frame.array == 1 ? phaseBox_->value() : 0),
            static_cast<uint8_t>(frame.array == 0 ? phaseBox_->value() : 0),
            static_cast<uint8_t>(frame.array == 1 ? attenBox_->value() : 0),
            static_cast<uint8_t>(frame.array == 0 ? attenBox_->value() : 0),
            0, 0, static_cast<uint8_t>(frame.array == 1 ? 1 : 2), 0, 0, 0, 0};
    } else {
        for (auto *editor : fieldEditors_) frame.payload.push_back(static_cast<uint8_t>(editor->value()));
    }
    return frame;
}

void MainWindow::updatePreview() {
    if (!preview_ || !pages_) return;
    const auto frame = currentFrame();
    preview_->setText(bytesText(beam::encode(frame)));
    preview_->setCursorPosition(0);
    const auto error = beam::validate(beam::modes()[modeIndex_], frame.array, frame.payload);
    preview_->setToolTip(error.empty() ? QStringLiteral("协议字段检查通过") : zh(error.c_str()));
    if (modeIndex_ == 1) physicalLabel_->setText(
        QStringLiteral("≈ %1° / %2 dB").arg(phaseBox_->value() * 5.625, 0, 'f', 3)
                                       .arg(attenBox_->value() * 0.5, 0, 'f', 1));
    updateControls();
}

void MainWindow::updateChannelTable() {
    if (!channels_) return;
    loadingTable_ = true;
    const int array = arrayBox_->currentData().toInt();
    const int line = lineBox_->value();
    for (int row = 0; row < 16; ++row) {
        const ChannelState state = array <= 1 ? channelStates_[stateIndex(array, line, row)] : ChannelState{};
        auto *check = new QTableWidgetItem;
        check->setFlags(Qt::ItemIsEnabled | Qt::ItemIsUserCheckable);
        check->setCheckState(Qt::Unchecked);
        channels_->setItem(row, 0, check);
        const QStringList values{QStringLiteral("SDI%1").arg(row / 4 + 1),
            QString::number(row % 4), state.enable ? QStringLiteral("开") : QStringLiteral("关"),
            QString::number(state.phase), QString::number(state.attenuation), state.result};
        for (int col = 1; col <= 6; ++col) {
            auto *item = new QTableWidgetItem(values[col - 1]);
            item->setFlags(Qt::ItemIsSelectable | Qt::ItemIsEnabled);
            channels_->setItem(row, col, item);
        }
    }
    channels_->selectRow(0);
    loadingTable_ = false;
    updateChannelEditor();
}

void MainWindow::updateChannelEditor() {
    if (loadingTable_ || !channels_ || !enableBox_) return;
    const int array = arrayBox_->currentData().toInt();
    const int row = channels_->currentRow();
    if (array > 1 || row < 0) return;
    const ChannelState state = channelStates_[stateIndex(array, lineBox_->value(), row)];
    const QSignalBlocker b1(enableBox_), b2(phaseBox_), b3(attenBox_);
    enableBox_->setCurrentIndex(state.enable ? 1 : 0);
    phaseBox_->setValue(state.phase);
    attenBox_->setValue(state.attenuation);
    physicalLabel_->setText(QStringLiteral("≈ %1° / %2 dB")
        .arg(state.phase * 5.625, 0, 'f', 3).arg(state.attenuation * 0.5, 0, 'f', 1));
}

void MainWindow::applyChannelEditor() {
    const int array = arrayBox_->currentData().toInt();
    const int row = channels_->currentRow();
    if (array > 1 || row < 0) return;
    ChannelState &state = channelStates_[stateIndex(array, lineBox_->value(), row)];
    state.enable = enableBox_->currentIndex() == 1;
    state.phase = phaseBox_->value();
    state.attenuation = attenBox_->value();
    state.result = QStringLiteral("待发送");
    channels_->item(row, 3)->setText(state.enable ? QStringLiteral("开") : QStringLiteral("关"));
    channels_->item(row, 4)->setText(QString::number(state.phase));
    channels_->item(row, 5)->setText(QString::number(state.attenuation));
    channels_->item(row, 6)->setText(state.result);
    updatePreview();
}

MainWindow::Job MainWindow::channelJob(int row) const {
    const int array = arrayBox_->currentData().toInt();
    const int line = lineBox_->value();
    const ChannelState state = channelStates_[stateIndex(array, line, row)];
    beam::Frame frame{0x40, static_cast<uint8_t>(array),
        {static_cast<uint8_t>(line), static_cast<uint8_t>(row / 4),
         static_cast<uint8_t>(row % 4), static_cast<uint8_t>(state.enable ? 1 : 0),
         static_cast<uint8_t>(array == 1 ? state.phase : 0),
         static_cast<uint8_t>(array == 0 ? state.phase : 0),
         static_cast<uint8_t>(array == 1 ? state.attenuation : 0),
         static_cast<uint8_t>(array == 0 ? state.attenuation : 0),
         0, 0, static_cast<uint8_t>(array == 1 ? 1 : 2), 0, 0, 0, 0}};
    return {frame, QStringLiteral("线阵%1 / SDI%2 / 通道%3")
            .arg(line).arg(row / 4 + 1).arg(row % 4), row, array, line};
}

void MainWindow::sendCurrent() {
    beam::Frame frame = currentFrame();
    const std::string error = beam::validate(beam::modes()[modeIndex_], frame.array, frame.payload);
    if (!error.empty()) {
        QMessageBox::warning(this, QStringLiteral("字段不符合协议"), zh(error.c_str())); return;
    }
    if (transportBox_->currentIndex() == 1 && (frame.command == 0xF1 || frame.command == 0xF5)) {
        const QString warning = frame.command == 0xF5
            ? QStringLiteral("将擦除所选阵面在 U22 数据 Flash 中的全部 8 MiB 分区。操作可能持续数分钟，中断后会留下部分已擦除数据。")
            : QStringLiteral("将擦除 U22 的完整 64 KiB 扇区，同扇区其他通道记录也会被清除。请核对阵面、线阵或频点序号。");
        if (QMessageBox::warning(this, QStringLiteral("确认擦除"), warning,
                QMessageBox::Yes | QMessageBox::Cancel, QMessageBox::Cancel) != QMessageBox::Yes) return;
    }
    if (modeIndex_ == 1) {
        applyChannelEditor();
        enqueue(channelJob(channels_->currentRow() < 0 ? 0 : channels_->currentRow()));
    } else enqueue({frame, zh(beam::modes()[modeIndex_].name)});
}

void MainWindow::sendChecked() {
    if (!connected_ || uncertain_) {
        QMessageBox::warning(this, QStringLiteral("当前不能发送"), uncertain_
            ? QStringLiteral("上一条命令结果未知，请重连后继续")
            : QStringLiteral("请先连接模拟设备或串口"));
        return;
    }
    if (arrayBox_->currentData().toInt() > 1) {
        QMessageBox::warning(this, QStringLiteral("阵面选择"),
                             QStringLiteral("批量通道配置需选择接收或发射阵面")); return;
    }
    int count = 0;
    for (int row = 0; row < 16; ++row) {
        if (channels_->item(row, 0)->checkState() == Qt::Checked) {
            enqueue(channelJob(row)); ++count;
        }
    }
    if (count == 0) QMessageBox::information(this, QStringLiteral("未选择通道"),
                                               QStringLiteral("请先勾选要发送的通道"));
}

void MainWindow::enqueue(Job job) {
    if (!connected_ || uncertain_) {
        QMessageBox::warning(this, QStringLiteral("当前不能发送"), uncertain_
            ? QStringLiteral("上一条命令超时，结果未知。请断开并重新连接后继续。")
            : QStringLiteral("请先连接模拟设备或串口。")); return;
    }
    queue_.enqueue(std::move(job));
    startNext();
}

void MainWindow::startNext() {
    if (!connected_ || uncertain_ || active_ || queue_.isEmpty()) return;
    active_ = queue_.dequeue();
    const auto bytes = beam::encode(active_->frame);
    logEntry(QStringLiteral("发送"), active_->description + QStringLiteral("；等待执行应答"), bytesText(bytes));
    resultLabel_->setText(QStringLiteral("板端状态：等待应答"));
    if (transportBox_->currentIndex() == 1) {
        QByteArray data(reinterpret_cast<const char *>(bytes.data()), static_cast<qsizetype>(bytes.size()));
        if (port_->write(data) != data.size()) {
            logEntry(QStringLiteral("错误"), QStringLiteral("串口写入失败：") + port_->errorString());
            markTimeout(); return;
        }
    } else {
        const int behavior = simulateBox_->currentIndex();
        if (behavior != 5) {
            uint8_t status = behavior == 1 ? 4 : behavior == 2 ? 3 : 0;
            std::vector<uint8_t> extra;
            if (status == 0 && (active_->frame.command == 0x20 || active_->frame.command == 0xA0))
                status = 5;
            if (active_->frame.command == 0xE0 && status == 0) extra = {1, 0, 0, 0, 0};
            if (active_->frame.command == 0xF3 && status == 0) extra = {0, 0, 0, 0, 0};
            auto answer = beam::response(active_->frame.array, active_->frame.command, status, extra);
            if (behavior == 4) answer[answer.size() - 2] ^= 1;
            QTimer::singleShot(90, this, [this, answer, behavior] {
                if (!active_ || !connected_) return;
                if (behavior == 3) {
                    receiveBytes(answer.data(), 3);
                    QTimer::singleShot(50, this, [this, answer] {
                        if (active_ && connected_) receiveBytes(answer.data() + 3, answer.size() - 3);
                    });
                } else receiveBytes(answer.data(), answer.size());
            });
        }
    }
    timeout_->start(active_->frame.command == 0xF5 ? 600000 :
                    active_->frame.command == 0xF1 ? 30000 :
                    active_->frame.command >= 0xF2 ? 10000 : 3000);
    updateControls();
}

void MainWindow::receiveBytes(const uint8_t *data, size_t size) {
    for (const auto &frame : incoming_.push(data, size)) {
        if (transportBox_->currentIndex() == 0)
            logEntry(QStringLiteral("接收"), QStringLiteral("模拟设备应答"), bytesText(beam::encode(frame)));
        handleResponse(frame);
    }
}

void MainWindow::handleResponse(const beam::Frame &frame) {
    if (frame.command != 0x7F || frame.payload.size() < 2 || !active_ ||
        frame.array != active_->frame.array || frame.payload[0] != active_->frame.command) {
        logEntry(QStringLiteral("提示"), QStringLiteral("非当前命令的应答，已忽略")); return;
    }
    timeout_->stop();
    const uint8_t status = frame.payload[1];
    const QString message = statusName(status);
    logEntry(QStringLiteral("结果"), active_->description + QStringLiteral("：") + message);
    resultLabel_->setText(QStringLiteral("板端状态：") + message);
    if (active_->channelRow >= 0 && active_->channelArray < 2) {
        auto &state = channelStates_[stateIndex(active_->channelArray,
                                                active_->channelLine, active_->channelRow)];
        const auto &sent = active_->frame.payload;
        const int sentPhase = active_->channelArray == 1 ? sent[4] : sent[5];
        const int sentAtt = active_->channelArray == 1 ? sent[6] : sent[7];
        const bool desiredChanged = state.enable != (sent[3] != 0) ||
                                    state.phase != sentPhase || state.attenuation != sentAtt;
        state.result = status == 0
            ? (desiredChanged ? QStringLiteral("旧命令成功；新值待发送") : QStringLiteral("应答成功"))
            : message;
        if (arrayBox_->currentData().toInt() == active_->channelArray &&
            lineBox_->value() == active_->channelLine)
            channels_->item(active_->channelRow, 6)->setText(state.result);
    }
    if (frame.payload[0] == 0xE0 && frame.payload.size() >= 7)
        logEntry(QStringLiteral("状态"), QStringLiteral("阵面初始化=%1 调度忙=%2 错误锁存=%3 U22探测完成=%4 U22有响应=%5 接收线阵掩码=%6 发射线阵掩码=%7")
            .arg(frame.payload[2] & 1).arg(frame.payload[3] & 1)
            .arg(frame.payload[4] & 1).arg((frame.payload[3] >> 1) & 1)
            .arg((frame.payload[4] >> 1) & 1)
            .arg(frame.payload[5], 2, 16, QChar('0')).arg(frame.payload[6], 2, 16, QChar('0')));
    if (frame.payload[0] == 0xF3 && status == 0 && frame.payload.size() >= 7)
        logEntry(QStringLiteral("Flash重载"), QStringLiteral("有效记录=%1；末条有效记录摘要=%2 %3 %4（重载不触发阵面写入）")
            .arg(frame.payload[2] | (frame.payload[3] << 8))
            .arg(frame.payload[4], 2, 16, QChar('0'))
            .arg(frame.payload[5], 2, 16, QChar('0'))
            .arg(frame.payload[6], 2, 16, QChar('0')));
    active_.reset();
    updateControls();
    startNext();
}

void MainWindow::markTimeout() {
    if (!active_) return;
    const QString target = active_->description;
    if (active_->channelRow >= 0 && active_->channelArray < 2) {
        auto &state = channelStates_[stateIndex(active_->channelArray,
                                                active_->channelLine, active_->channelRow)];
        state.result = QStringLiteral("结果未知");
        if (arrayBox_->currentData().toInt() == active_->channelArray &&
            lineBox_->value() == active_->channelLine)
            channels_->item(active_->channelRow, 6)->setText(state.result);
    }
    active_.reset(); queue_.clear(); timeout_->stop(); uncertain_ = true;
    resultLabel_->setText(QStringLiteral("板端状态：超时，执行结果未知；队列已停止"));
    logEntry(QStringLiteral("超时"), target + QStringLiteral("：不自动重发；断开重连后再操作"));
    updateControls();
}

void MainWindow::logEntry(const QString &direction, const QString &message, const QString &bytes) {
    const int row = log_->rowCount();
    log_->insertRow(row);
    const QStringList data{QDateTime::currentDateTime().toString("HH:mm:ss.zzz"), direction, message, bytes};
    for (int col = 0; col < 4; ++col) log_->setItem(row, col, new QTableWidgetItem(data[col]));
    log_->scrollToBottom();
}

void MainWindow::saveConfiguration() {
    QString path = QFileDialog::getSaveFileName(this, QStringLiteral("保存通道配置"), {},
                                               QStringLiteral("JSON配置 (*.json)"));
    if (path.isEmpty()) return;
    QJsonArray channels;
    for (const auto &state : channelStates_) {
        QJsonObject item;
        item["enable"] = state.enable; item["phase"] = state.phase;
        item["attenuation"] = state.attenuation;
        channels.append(item);
    }
    QJsonObject root;
    root["format"] = "beam-control-channel-config";
    root["version"] = 1;
    root["channels"] = channels;
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly) || file.write(QJsonDocument(root).toJson()) < 0)
        QMessageBox::warning(this, QStringLiteral("保存失败"), file.errorString());
    else logEntry(QStringLiteral("文件"), QStringLiteral("通道配置已保存；不代表板端状态"));
}

void MainWindow::loadConfiguration() {
    const QString path = QFileDialog::getOpenFileName(this, QStringLiteral("载入通道配置"), {},
                                                      QStringLiteral("JSON配置 (*.json)"));
    if (path.isEmpty()) return;
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        QMessageBox::warning(this, QStringLiteral("读取失败"), file.errorString()); return;
    }
    QJsonParseError error;
    const auto doc = QJsonDocument::fromJson(file.readAll(), &error);
    const auto root = doc.object();
    const auto items = root.value("channels").toArray();
    if (error.error != QJsonParseError::NoError || root.value("format").toString() !=
        "beam-control-channel-config" || root.value("version").toInt() != 1 || items.size() != 256) {
        QMessageBox::warning(this, QStringLiteral("文件不匹配"),
                             QStringLiteral("配置格式或256通道数量不正确")); return;
    }
    QVector<ChannelState> loaded(256);
    for (int i = 0; i < 256; ++i) {
        const auto item = items[i].toObject();
        const int phase = item.value("phase").toInt(-1);
        const int att = item.value("attenuation").toInt(-1);
        if (!item.value("enable").isBool() || phase < 0 || phase > 63 || att < 0 || att > 63) {
            QMessageBox::warning(this, QStringLiteral("文件不匹配"),
                                 QStringLiteral("第%1通道字段越界或类型错误").arg(i)); return;
        }
        loaded[i] = {item.value("enable").toBool(), phase, att, QStringLiteral("待发送")};
    }
    channelStates_ = std::move(loaded);
    updateChannelTable(); updatePreview();
    logEntry(QStringLiteral("文件"), QStringLiteral("通道配置已载入为待发送值；尚未写入板卡"));
}

void MainWindow::exportLog() {
    const QString path = QFileDialog::getSaveFileName(this, QStringLiteral("导出通信日志"), {},
                                                       QStringLiteral("CSV日志 (*.csv)"));
    if (path.isEmpty()) return;
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        QMessageBox::warning(this, QStringLiteral("导出失败"), file.errorString()); return;
    }
    QTextStream out(&file);
    out.setEncoding(QStringConverter::Utf8);
    out << QStringLiteral("时间,方向,说明,字节\n");
    for (int row = 0; row < log_->rowCount(); ++row) {
        for (int col = 0; col < 4; ++col) {
            if (col) out << ',';
            QString value = log_->item(row, col)->text();
            value.replace('"', QStringLiteral("\"\""));
            out << '"' << value << '"';
        }
        out << '\n';
    }
    out.flush();
    if (file.error() != QFile::NoError)
        QMessageBox::warning(this, QStringLiteral("导出失败"), file.errorString());
}

void MainWindow::updateControls() {
    if (!transportBox_) return;
    const bool sim = transportBox_->currentIndex() == 0;
    portBox_->setEnabled(!sim && !connected_);
    simulateBox_->setEnabled(sim);
    transportBox_->setEnabled(!connected_);
    connectButton_->setText(connected_ ? QStringLiteral("断开") : QStringLiteral("连接"));
    connectionLabel_->setText(connected_ ? (sim ? QStringLiteral("● 模拟已连接")
                                            : QStringLiteral("● 串口已连接"))
                                         : QStringLiteral("○ 未连接"));
    const bool canSend = connected_ && !uncertain_;
    if (sendButton_) sendButton_->setEnabled(canSend);
    if (batchButton_) batchButton_->setEnabled(canSend && modeIndex_ == 1);
    if (stopButton_) stopButton_->setEnabled(!queue_.isEmpty());
    statusBar()->showMessage(uncertain_ ? QStringLiteral("上条命令结果未知，请重连")
        : active_ ? QStringLiteral("等待应答 · 队列剩余 %1 条").arg(queue_.size())
        : QStringLiteral("空闲 · 队列剩余 %1 条").arg(queue_.size()));
}
