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

#include "macosaccessibility.h"

#import <Foundation/Foundation.h>
#include <objc/message.h>
#include <objc/runtime.h>

#include <cstdlib>
#include <cstring>

#include <QAccessible>
#include <QDebug>

namespace
{
    IMP originalDealloc = nullptr;
    IMP originalRemoveElements = nullptr;
    ptrdiff_t accessibleIdOffset = 0;

    Method findOwnMethod(Class cls, SEL selector)
    {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cls, &count);
        Method result = nullptr;
        for (unsigned int i = 0; i < count; ++i)
        {
            if (method_getName(methods[i]) == selector)
            {
                result = methods[i];
                break;
            }
        }
        std::free(methods);
        return result;
    }

    bool isSyntheticElement(id element)
    {
        return reinterpret_cast<BOOL (*)(id, SEL)>(objc_msgSend)(
            element, sel_registerName("isManagedByParent"));
    }

    void deallocElement(id element, SEL selector)
    {
        // Qt's synthetic rows, columns and unresolved cells borrow the table's
        // accessibility ID. They must not delete its interface when released.
        if (isSyntheticElement(element))
        {
            auto *accessibleId = reinterpret_cast<QAccessible::Id *>(
                reinterpret_cast<char *>(element) + accessibleIdOffset);
            *accessibleId = 0;
        }
        reinterpret_cast<void (*)(id, SEL)>(originalDealloc)(element, selector);
    }

    void removeElementsFromCache(id cls, SEL selector, NSArray *elements)
    {
        NSMutableArray *ownedElements = [NSMutableArray arrayWithCapacity:elements.count];
        for (id element in elements)
        {
            if (!isSyntheticElement(element))
                [ownedElements addObject:element];
        }
        reinterpret_cast<void (*)(id, SEL, NSArray *)>(originalRemoveElements)(cls, selector, ownedElements);
    }
}

void MacUtils::initializeAccessibilityWorkaround()
{
    // Qt's Cocoa bridge deletes borrowed IDs during native table-cell replacement.
    // This frees selectedItems() entries while accessibilitySelectedChildren is
    // still iterating them. Only patch when the private runtime layout matches:
    // every patched method must be defined by QMacAccessibilityElement itself.
    if (originalDealloc)
        return;

    const Class cls = NSClassFromString(@"QMacAccessibilityElement");
    if (!cls)
        return;

    const Ivar accessibleId = class_getInstanceVariable(cls, "axid");
    const Method managedByParent = findOwnMethod(cls, sel_registerName("isManagedByParent"));
    const Method dealloc = findOwnMethod(cls, sel_registerName("dealloc"));
    const Method removeElements = findOwnMethod(object_getClass(cls), sel_registerName("removeElementsFromCache:"));
    // Qt versions before 6.9.1 have no shared-ID cache cleanup and are not affected.
    if (!removeElements)
        return;

    if (!accessibleId || !managedByParent || !dealloc
        || (std::strcmp(ivar_getTypeEncoding(accessibleId), @encode(QAccessible::Id)) != 0))
    {
        qWarning("Cannot install Qt Cocoa accessibility ownership workaround");
        return;
    }

    accessibleIdOffset = ivar_getOffset(accessibleId);
    originalDealloc = method_setImplementation(dealloc, reinterpret_cast<IMP>(deallocElement));
    originalRemoveElements = method_setImplementation(removeElements, reinterpret_cast<IMP>(removeElementsFromCache));
}
