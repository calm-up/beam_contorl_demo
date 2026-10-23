#include "mainwindow.h"

#include <QApplication>
#include <QComboBox>
#include <QLabel>
#include <QLineEdit>
#include <QPushButton>
#include <QTableWidget>
#include <QTest>
#include <iostream>

int main(int argc, char *argv[]) {
    QApplication app(argc, argv);
    MainWindow window;
    window.show();
    auto *preview = window.findChild<QLineEdit *>("framePreview");
    auto *connectButton = window.findChild<QPushButton *>("connectButton");
    auto *sendButton = window.findChild<QPushButton *>("sendButton");
    auto *result = window.findChild<QLabel *>("resultLabel");
    auto *log = window.findChild<QTableWidget *>("communicationLog");
    auto *behavior = window.findChild<QComboBox *>("simulateBehavior");
    if (!preview || !connectButton || !sendButton || !result || !log || !behavior) {
        std::cerr << "missing: preview=" << bool(preview) << " connect=" << bool(connectButton)
                  << " send=" << bool(sendButton) << " result=" << bool(result)
                  << " log=" << bool(log) << " simulator=" << bool(behavior) << '\n';
        return 1;
    }
    if (!preview->text().startsWith("AA DD 01 17 40 00")) {
        std::cerr << "preview=" << preview->text().toStdString() << '\n';
        return 2;
    }
    connectButton->click();
    sendButton->click();
    QTest::qWait(250);
    if (!result->text().contains(QStringLiteral("成功")) || log->rowCount() < 3) {
        std::cerr << "result=" << result->text().toStdString() << " logrows=" << log->rowCount() << '\n';
        return 3;
    }
    behavior->setCurrentIndex(1);
    sendButton->click();
    QTest::qWait(250);
    if (!result->text().contains(QStringLiteral("忙"))) return 4;
    connectButton->click();
    return 0;
}
