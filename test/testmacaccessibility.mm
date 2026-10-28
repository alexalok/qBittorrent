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

#include <memory>

#include <QAccessible>
#include <QApplication>
#include <QSortFilterProxyModel>
#include <QStandardItemModel>
#include <QTableView>
#include <QTableWidget>
#include <QTest>
#include <QTreeView>

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

    void insertedRowsPreserveCellInterfaces_data() const
    {
        QTest::addColumn<bool>("useTreeView");
        QTest::newRow("table") << false;
        QTest::newRow("tree-with-proxy") << true;
    }

    void insertedRowsPreserveCellInterfaces() const
    {
        QFETCH(bool, useTreeView);
        QStandardItemModel model(2, 3);
        model.setData(model.index(0, 0), QStringLiteral("Retained cell"));
        QSortFilterProxyModel proxy;
        proxy.setSourceModel(&model);
        std::unique_ptr<QAbstractItemView> view;
        QAccessibleInterface *iface = nullptr;
        QAccessibleInterface *cell = nullptr;
        QAccessible::Id cellId = 0;
        QAccessible::Id tableId = 0;
        id native = nil;

        @autoreleasepool
        {
            if (useTreeView)
                view = std::make_unique<QTreeView>();
            else
                view = std::make_unique<QTableView>();
            view->setModel(&proxy);
            view->setSelectionBehavior(QAbstractItemView::SelectRows);
            view->show();
            QApplication::processEvents();
            view->selectionModel()->select(proxy.index(0, 0), QItemSelectionModel::Select | QItemSelectionModel::Rows);
            QAccessible::setActive(true);
            iface = QAccessible::queryAccessibleInterface(view.get());
            QVERIFY(iface);
            tableId = QAccessible::uniqueId(iface);
            cell = iface->tableInterface()->cellAt(0, 0);
            QVERIFY(cell);
            cellId = QAccessible::uniqueId(cell);
            const Class cls = NSClassFromString(@"QMacAccessibilityElement");
            QVERIFY(cls);
            native = reinterpret_cast<id (*)(id, SEL, QAccessible::Id)>(objc_msgSend)(
                cls, sel_registerName("elementWithId:"), tableId);
            QVERIFY(native);
            NSArray *selected = [native accessibilitySelectedChildren];
            QCOMPARE(selected.count, 3UL);
        }
        for (int iteration = 0; iteration < 10; ++iteration)
        {
            @autoreleasepool
            {
                // Rebuilding native rows releases the old row and its real cells.
                QVERIFY(model.insertRow(0));
                view->doItemsLayout();
                // Cocoa omits offscreen cells from accessibilitySelectedChildren.
                view->scrollTo(proxy.index(iteration + 1, 0));
            }
            QCOMPARE(QAccessible::accessibleInterface(cellId), cell);
            QVERIFY(cell->isValid());
            QCOMPARE(iface->tableInterface()->cellAt(iteration + 1, 0), cell);

            @autoreleasepool
            {
                NSArray *selected = [native accessibilitySelectedChildren];
                QCOMPARE(selected.count, 3UL);
                QCOMPARE(QString::fromNSString([selected[0] accessibilityTitle]), QStringLiteral("Retained cell"));
                NSArray *rows = [native accessibilityRows];
                // Real native cells must be recreated at their current position.
                QVERIFY([selected[0] accessibilityParent] == rows[iteration + 1]);
            }
            QCOMPARE(QAccessible::accessibleInterface(cellId), cell);
            QCOMPARE(iface->tableInterface()->rowCount(), iteration + 3);
        }

        @autoreleasepool
        {
            model.clear();
        }
        QVERIFY(!QAccessible::accessibleInterface(cellId));
        @autoreleasepool
        {
            view.reset();
        }
        QVERIFY(!QAccessible::accessibleInterface(tableId));
    }

    void removedRowsRecreateNativeCells() const
    {
        std::unique_ptr<QTableWidget> table;
        QAccessibleInterface *iface = nullptr;
        QAccessibleInterface *cell = nullptr;
        QAccessible::Id cellId = 0;
        id native = nil;
        @autoreleasepool
        {
            table = std::make_unique<QTableWidget>(3, 3);
            table->setSelectionBehavior(QAbstractItemView::SelectRows);
            table->resize(640, 480);
            table->show();
            QApplication::processEvents();
            table->selectRow(2);
            table->scrollTo(table->model()->index(2, 0));
            QAccessible::setActive(true);
            iface = QAccessible::queryAccessibleInterface(table.get());
            QVERIFY(iface);
            cell = iface->tableInterface()->cellAt(2, 0);
            QVERIFY(cell);
            cellId = QAccessible::uniqueId(cell);
            const Class cls = NSClassFromString(@"QMacAccessibilityElement");
            QVERIFY(cls);
            native = reinterpret_cast<id (*)(id, SEL, QAccessible::Id)>(objc_msgSend)(
                cls, sel_registerName("elementWithId:"), QAccessible::uniqueId(iface));
            QVERIFY(native);
            QCOMPARE([[native accessibilitySelectedChildren] count], 3UL);
        }
        @autoreleasepool
        {
            table->removeRow(0);
        }
        QCOMPARE(QAccessible::accessibleInterface(cellId), cell);
        @autoreleasepool
        {
            NSArray *selected = [native accessibilitySelectedChildren];
            QCOMPARE(selected.count, 3UL);
            NSArray *rows = [native accessibilityRows];
            QCOMPARE(rows.count, 2UL);
            // The cached old position was 2, now outside the native row array.
            QVERIFY([selected[0] accessibilityParent] == rows[1]);
            table->insertColumn(3);
            table->removeColumn(3);
        }
        QCOMPARE(QAccessible::accessibleInterface(cellId), cell);
        QCOMPARE(iface->tableInterface()->cellAt(1, 0), cell);
        @autoreleasepool
        {
            table->removeRow(1);
        }
        QVERIFY(!QAccessible::accessibleInterface(cellId));
    }
};

QTEST_MAIN(TestMacAccessibility)
#include "testmacaccessibility.moc"
