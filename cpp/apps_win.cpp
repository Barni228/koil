// The apps Explorer's Open With menu offers for a file, and opening the
// file with one of them, or another app of a name or path the user typed
// (appsToOpen and openWithApp in native.h), through the shell's
// association handlers and ShellExecute. Windows only, which build.rs adds
// only there (native.cpp has what the others get): apart, as windows.h's
// macros would clash with native.cpp's names.

#include "native.h"

#include <QtCore/QFileInfo>
#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>

#include <string>

#include <QtCore/qt_windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <shobjidl.h>
#include <wrl/client.h>

using Microsoft::WRL::ComPtr;

namespace {

// COM on this thread while it's in scope. The GUI thread has it already
// (Qt's OleInitialize), and then this only counts once more.
struct ComScope
{
  HRESULT result = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  ~ComScope()
  {
    if (SUCCEEDED(result))
      CoUninitialize();
  }
};

// What Windows looks a file's apps up by: its extension, as Explorer reads
// it (a dotfile's whole name, `.gitignore`), or `.` for none.
std::wstring
extensionOf(const QString& path)
{
  const QString name = QFileInfo(path).fileName();
  const qsizetype dot = name.lastIndexOf(u'.');
  return (dot < 0 ? QStringLiteral(".") : name.sliced(dot)).toStdWString();
}

// A string the shell gave, freed after.
QString
taken(LPWSTR text)
{
  const QString string = text ? QString::fromWCharArray(text) : QString();
  CoTaskMemFree(text);
  return string;
}

// The handlers Explorer's Open With menu shows for `extension`, or null.
ComPtr<IEnumAssocHandlers>
handlersOf(const std::wstring& extension)
{
  ComPtr<IEnumAssocHandlers> handlers;
  if (FAILED(SHAssocEnumHandlers(extension.c_str(), ASSOC_FILTER_RECOMMENDED, &handlers)))
    return nullptr;
  return handlers;
}

// The executable the file type's default app runs, or empty.
QString
defaultApp(const std::wstring& extension)
{
  wchar_t path[MAX_PATH * 2];
  DWORD length = DWORD(std::size(path));
  if (FAILED(AssocQueryStringW(ASSOCF_NOTRUNCATE, ASSOCSTR_EXECUTABLE, extension.c_str(), L"open", path, &length)))
    return {};
  return QString::fromWCharArray(path);
}

} // namespace

QString
appsToOpen(const QString& path)
{
  QJsonArray apps;
  // Explorer has no Open With for a folder.
  if (!QFileInfo(path).isDir()) {
    ComScope com;
    const std::wstring extension = extensionOf(path);
    const QString standard = defaultApp(extension);
    const ComPtr<IEnumAssocHandlers> handlers = handlersOf(extension);
    ComPtr<IAssocHandler> handler;
    while (handlers && handlers->Next(1, &handler, nullptr) == S_OK) {
      LPWSTR name = nullptr;
      LPWSTR shown = nullptr;
      const QString app = SUCCEEDED(handler->GetName(&name)) ? taken(name) : QString();
      const QString title = SUCCEEDED(handler->GetUIName(&shown)) ? taken(shown) : QString();
      if (app.isEmpty())
        continue;
      apps.append(QJsonObject{
        { QStringLiteral("name"), title.isEmpty() ? QFileInfo(app).completeBaseName() : title },
        { QStringLiteral("path"), app },
        { QStringLiteral("default"), app.compare(standard, Qt::CaseInsensitive) == 0 },
      });
    }
  }
  return QString::fromUtf8(QJsonDocument(apps).toJson(QJsonDocument::Compact));
}

QString
openWithApp(const QString& path, const QString& app)
{
  ComScope com;
  const ComPtr<IEnumAssocHandlers> handlers = handlersOf(extensionOf(path));
  ComPtr<IAssocHandler> handler;
  bool found = false;
  while (!found && handlers && handlers->Next(1, &handler, nullptr) == S_OK) {
    LPWSTR name = nullptr;
    found = SUCCEEDED(handler->GetName(&name)) && taken(name).compare(app, Qt::CaseInsensitive) == 0;
  }
  const std::wstring file = QString(path).replace(u'/', u'\\').toStdWString();
  // One it isn't listed for (or no longer is), with the path as its
  // argument, quoted (a path can't have a `"`). No dialog if it fails.
  if (!found) {
    const std::wstring program = app.toStdWString();
    const std::wstring argument = L"\"" + file + L"\"";
    SHELLEXECUTEINFOW info = {};
    info.cbSize = sizeof(info);
    info.fMask = SEE_MASK_NOASYNC | SEE_MASK_FLAG_NO_UI;
    info.lpVerb = L"open";
    info.lpFile = program.c_str();
    info.lpParameters = argument.c_str();
    info.nShow = SW_SHOWNORMAL;
    if (ShellExecuteExW(&info))
      return {};
    const DWORD error = GetLastError();
    return error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND
             ? QStringLiteral("there's no app of that name")
             : qt_error_string(int(error)).trimmed();
  }
  ComPtr<IShellItem> item;
  ComPtr<IDataObject> data;
  HRESULT result = SHCreateItemFromParsingName(file.c_str(), nullptr, IID_PPV_ARGS(&item));
  if (SUCCEEDED(result))
    result = item->BindToHandler(nullptr, BHID_DataObject, IID_PPV_ARGS(&data));
  if (SUCCEEDED(result))
    result = handler->Invoke(data.Get());
  return SUCCEEDED(result) ? QString() : qt_error_string(int(result)).trimmed();
}
