/*
 * Bittorrent Client using Qt and libtorrent.
 * Copyright (C) 2026  Aleksei Chistiakov (alexalok)
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 *
 * In addition, as a special exception, the copyright holders give permission to
 * link this program with the OpenSSL project's "OpenSSL" library (or with
 * modified versions of it that use the same license as the "OpenSSL" library),
 * and distribute the linked executables. You must obey the GNU General Public
 * License in all respects for all of the code used other than "OpenSSL".  If you
 * modify file(s), you may extend this exception to your version of the file(s),
 * but you are not obligated to do so. If you do not wish to do so, delete this
 * exception statement from your version.
 */

#import <Cocoa/Cocoa.h>
#include <objc/message.h>

#include <QAccessible>
#include <QApplication>
#include <QTableWidget>
#include <QTest>
#include <QTreeWidget>

#include "gui/macosaccessibility.h"

class TestMacAccessibility final : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase() const
    {
        MacUtils::initializeAccessibilityWorkaround();
        MacUtils::initializeAccessibilityWorkaround();
    }

    void selectedChildren() const
    {
        QTableWidget table(2, 3);
        table.setSelectionBehavior(QAbstractItemView::SelectRows);
        table.selectRow(0);
        table.show();
        QApplication::processEvents();
        QAccessible::setActive(true);
        auto *iface = QAccessible::queryAccessibleInterface(&table);
        const auto tableId = QAccessible::uniqueId(iface);
        const Class cls = NSClassFromString(@"QMacAccessibilityElement");
        QVERIFY(cls);
        id native = reinterpret_cast<id (*)(id, SEL, QAccessible::Id)>(objc_msgSend)(
            cls, sel_registerName("elementWithId:"), tableId);
        QVERIFY(native);
        for (int iteration = 0; iteration < 3; ++iteration)
        {
            @autoreleasepool
            {
                NSArray *rows = [native accessibilityRows];
                QCOMPARE(rows.count, 2UL);
                NSArray *cells = [rows[0] accessibilityChildren];
                QCOMPARE(cells.count, 3UL);
                // Creating selected native cells replaces unresolved placeholders.
                NSArray *selected = [native accessibilitySelectedChildren];
                QCOMPARE(selected.count, 3UL);
                QCOMPARE(QAccessible::accessibleInterface(tableId), iface);
                QVERIFY(iface->isValid());
            }
            table.setRowCount(0);
            table.setRowCount(2);
            table.selectRow(0);
            QApplication::processEvents();
        }
    }
};

QTEST_MAIN(TestMacAccessibility)
#include "testmacaccessibility.moc"
