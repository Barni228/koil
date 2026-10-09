// "Open in Koil", the service packaging/macos/Info.plist declares (see
// watchFinderService in native.h). macOS shows it in Finder for the folders
// selected, in their right-click menu and the Services menu, and handles its
// shortcut, launching Koil if it isn't running; the folders come on the
// pasteboard.

#include "native.h"
#include "koil/src/ffi.cxx.h"

#include <QtCore/QHash>
#include <QtCore/QPointer>

#import <AppKit/AppKit.h>

namespace {

// The Document that opens the folder.
QPointer<QObject> document;

// A key equivalent as macOS keeps a service's ("@$e": its modifiers, then
// the key), as it shows one: ⇧⌘E.
QString
shortcutLabel(NSString* keyEquivalent)
{
  const QString text = QString::fromNSString(keyEquivalent);
  qsizetype keyStart = 0;
  while (keyStart < text.size() && QStringView(u"^~$@").contains(text[keyStart]))
    ++keyStart;
  if (keyStart == text.size())
    return {};
  const QStringView modifiers = QStringView(text).first(keyStart);
  QString label;
  if (modifiers.contains(u'^'))
    label += QStringLiteral("⌃");
  if (modifiers.contains(u'~'))
    label += QStringLiteral("⌥");
  if (modifiers.contains(u'$'))
    label += QStringLiteral("⇧");
  if (modifiers.contains(u'@'))
    label += QStringLiteral("⌘");
  const QString key = text.sliced(keyStart);
  // AppKit's function keys and arrows, in the Private Use Area.
  const char16_t c = key.size() == 1 ? key.front().unicode() : 0;
  if (c >= NSF1FunctionKey && c <= NSF35FunctionKey)
    return label + u'F' + QString::number(c - NSF1FunctionKey + 1);
  static const QHash<char16_t, QString> arrows = {
    { NSUpArrowFunctionKey, QStringLiteral("↑") },
    { NSDownArrowFunctionKey, QStringLiteral("↓") },
    { NSLeftArrowFunctionKey, QStringLiteral("←") },
    { NSRightArrowFunctionKey, QStringLiteral("→") },
  };
  return label + arrows.value(c, key.toUpper());
}

} // namespace

// Gets the service's requests (NSMessage in Info.plist).
@interface KoilServiceProvider : NSObject
- (void)openFolder:(NSPasteboard*)pasteboard userData:(NSString*)userData error:(NSString**)error;
@end

@implementation KoilServiceProvider
// Brings Koil to the front, as macOS doesn't for a service that gives
// nothing back, and has the Document open the first folder, as a drop of
// several opens the first.
- (void)openFolder:(NSPasteboard*)pasteboard userData:(NSString*)userData error:(NSString**)error
{
  NSArray<NSURL*>* urls = [pasteboard readObjectsForClasses:@[ NSURL.class ]
                                                    options:@{ NSPasteboardURLReadingFileURLsOnlyKey : @YES }];
  NSString* path = urls.firstObject.filePathURL.path;
  if (!path) {
    *error = @"Open in Koil got no folder";
    return;
  }
  if (!document)
    return;
  if (@available(macOS 14, *)) {
    [NSApp activate];
  } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [NSApp activateIgnoringOtherApps:YES];
#pragma clang diagnostic pop
  }
  folderRequested(document, QString::fromNSString(path));
}
@end

void
watchFinderService(QObject* folderDocument)
{
  document = folderDocument;
  // Before Koil finishes launching, so a request that launched it comes.
  static KoilServiceProvider* provider = [[KoilServiceProvider alloc] init];
  NSApp.servicesProvider = provider;
}

QString
finderServiceShortcut()
{
  NSBundle* bundle = NSBundle.mainBundle;
  NSDictionary* service = [bundle.infoDictionary[@"NSServices"] firstObject];
  if (!bundle.bundleIdentifier || ![service isKindOfClass:NSDictionary.class])
    return {};
  // Info.plist's NSKeyEquivalent ("J": ⌘ and the key, with ⇧ if it's
  // uppercase; or modifiers and a key, "^$K", as pbs keeps them), unless
  // the user changed it in System Settings, which keeps it in pbs's
  // preferences, with whether the service is on.
  NSString* key = service[@"NSKeyEquivalent"][@"default"];
  if (key.length == 1)
    key = [key.lowercaseString isEqualToString:key] ? [@"@" stringByAppendingString:key]
                                                     : [@"@$" stringByAppendingString:key.lowercaseString];
  CFPreferencesAppSynchronize(CFSTR("pbs"));
  NSDictionary* status = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("NSServicesStatus"), CFSTR("pbs")));
  NSString* name = [NSString stringWithFormat:@"%@ - %@ - %@",
                                              bundle.bundleIdentifier,
                                              service[@"NSMenuItem"][@"default"],
                                              service[@"NSMessage"]];
  NSDictionary* changed = [status isKindOfClass:NSDictionary.class] ? status[name] : nil;
  if ([changed isKindOfClass:NSDictionary.class]) {
    NSNumber* on = changed[@"enabled_services_menu"];
    if ([on isKindOfClass:NSNumber.class] && !on.boolValue)
      return {};
    if ([changed[@"key_equivalent"] isKindOfClass:NSString.class])
      key = changed[@"key_equivalent"];
  }
  return [key isKindOfClass:NSString.class] ? shortcutLabel(key) : QString();
}
