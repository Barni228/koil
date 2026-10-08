// "Open in Koil", the service packaging/macos/Info.plist declares (see
// watchFinderService in native.h). macOS shows it in Finder's Services menu
// and handles its shortcut, launching Koil if it isn't running; Koil then
// asks Finder, in osascript, which folder its front window shows.

#include "native.h"
#include "koil/src/ffi.cxx.h"

#include <QtCore/QHash>
#include <QtCore/QPointer>
#include <QtCore/QProcess>

#import <AppKit/AppKit.h>

namespace {

// Asks Finder for the folder its front window shows, or the desktop if it
// has none. A folder's POSIX path ends with "/".
const char* const finderScript = R"(tell application "Finder"
  if (count of Finder windows) is 0 then return POSIX path of (desktop as alias)
  return POSIX path of (target of front Finder window as alias)
end tell)";

// The Document that opens the folder, and the osascript asking for it.
QPointer<QObject> document;
QPointer<QProcess> asking;

// Why osascript couldn't read Finder's folder, from its `error` output.
QString
finderError(const QString& error)
{
  if (error.contains(u"(-1743)"))
    return QStringLiteral("Koil can't ask Finder which folder it shows: allow it in System "
                          "Settings > Privacy & Security > Automation");
  // The window shows no folder, or none with a path (Recents, AirDrop).
  if (error.contains(u"(-1700)") || error.contains(u"(-1728)"))
    return QStringLiteral("Finder's window shows no folder");
  const QString why = error.section(QStringLiteral("execution error: "), 1).trimmed();
  return QStringLiteral("Can't read Finder's folder: ") + (why.isEmpty() ? error.trimmed() : why);
}

// Brings Koil to the front, and has the Document open `path`, or show why
// it couldn't be read. macOS doesn't activate an app for a service that
// gives it nothing back.
void
report(const QString& path, const QString& error)
{
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
  folderRequested(document, path, error);
}

// Asks Finder for its folder, in osascript, so Koil isn't kept waiting
// while Finder answers (or macOS asks the user to allow it). Finder waits
// for the service to return, so it answers only after that.
void
askFinder()
{
  if (!document || asking)
    return;
  auto* process = new QProcess(document);
  asking = process;
  QObject::connect(process, &QProcess::finished, process, [process](int code, QProcess::ExitStatus status) {
    process->deleteLater();
    QString path = QString::fromUtf8(process->readAllStandardOutput());
    if (path.endsWith(u'\n'))
      path.chop(1);
    if (status == QProcess::NormalExit && code == 0 && !path.isEmpty())
      report(path, {});
    else
      report({}, finderError(QString::fromUtf8(process->readAllStandardError())));
  });
  QObject::connect(process, &QProcess::errorOccurred, process, [process](QProcess::ProcessError error) {
    if (error != QProcess::FailedToStart)
      return;
    process->deleteLater();
    report({}, QStringLiteral("Can't ask Finder which folder it shows: osascript didn't start"));
  });
  process->start(QStringLiteral("/usr/bin/osascript"), { QStringLiteral("-e"), QString::fromUtf8(finderScript) });
}

// A key equivalent as macOS keeps a service's ("@$e": its modifiers, then
// the key), as it shows one: ⇧⌘J.
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
- (void)openFinderFolder:(NSPasteboard*)pasteboard userData:(NSString*)userData error:(NSString**)error;
@end

@implementation KoilServiceProvider
- (void)openFinderFolder:(NSPasteboard*)pasteboard userData:(NSString*)userData error:(NSString**)error
{
  askFinder();
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
  // uppercase), unless the user changed it in System Settings, which keeps
  // it in pbs's preferences, with whether the service is on.
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
