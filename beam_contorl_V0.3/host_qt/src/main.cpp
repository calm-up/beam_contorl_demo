#include "mainwindow.h"

#include <QApplication>
#include <QFont>
#include <QTimer>
#include <QStringList>

int main(int argc, char *argv[]) {
    QApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("阵列波控调试工具"));
    app.setOrganizationName(QStringLiteral("BeamControl"));
    QFont font(QStringLiteral("Microsoft YaHei UI"), 10);
    app.setFont(font);
    MainWindow window;
    window.show();
    const QStringList arguments = app.arguments();
    if (arguments.size() == 3 && arguments[1] == "--screenshot") {
        QTimer::singleShot(500, &window, [&window, path = arguments[2], &app] {
            window.grab().save(path);
            app.quit();
        });
    }
    return app.exec();
}
