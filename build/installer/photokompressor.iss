; Photokompressor Windows installer.
;
; Not compiled by hand - build\package.ps1 stages a framework-dependent publish and then
; calls ISCC with the three defines below. Compile manually only for a quick look:
;
;   ISCC /DAppVersion=1.2.0 /DStageDir=..\..\dist\Photokompressor-1.2.0-win-x64 /DOutDir=..\..\dist photokompressor.iss
;
; The output is framework-dependent: it carries the app and its native image libraries but
; not the .NET runtime. On a machine without the .NET 8 Desktop Runtime the wizard downloads
; it from Microsoft (aka.ms) and installs it silently; on a machine that already has it,
; nothing extra is fetched or installed.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef StageDir
  #define StageDir "..\..\dist\Photokompressor-" + AppVersion + "-win-x64"
#endif
#ifndef OutDir
  #define OutDir "..\..\dist"
#endif

#define AppName "Photokompressor"
#define AppExe "Photokompressor.exe"
#define AppPublisher "antidot.gr"
#define AppUrl "https://github.com/Anti-super-code/Photokompressor"
; Stable channel link - always the latest 8.0.x Desktop Runtime, x64.
#define DotNetUrl "https://aka.ms/dotnet/8.0/windowsdesktop-runtime-win-x64.exe"

[Setup]
; Never change AppId - it is how upgrades and uninstall find a prior install.
AppId={{20CDB58D-F35A-4FAD-B914-B2AFFFC42983}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}
AppUpdatesURL={#AppUrl}
VersionInfoVersion={#AppVersion}
VersionInfoCompany={#AppPublisher}
VersionInfoProductName={#AppName}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableDirPage=auto
UninstallDisplayName={#AppName} {#AppVersion}
UninstallDisplayIcon={app}\{#AppExe}
OutputDir={#OutDir}
OutputBaseFilename=Photokompressor-Setup-{#AppVersion}
; No admin: lands in %LOCALAPPDATA%\Programs\Photokompressor. The user can still pick a
; machine-wide location, which elevates. The right-click verb is per-user (HKCU) either way.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
WizardStyle=modern
WizardImageFile=wizard-large-164.png,wizard-large-246.png,wizard-large-328.png,wizard-large-410.png
WizardSmallImageFile=wizard-small-55.png,wizard-small-83.png,wizard-small-110.png,wizard-small-138.png
SetupIconFile=..\..\src\Photokompressor\Assets\photokompressor.ico
Compression=lzma2/max
SolidCompression=yes
; Make Setup offer to close a running window before an upgrade rather than failing on a
; locked exe. MutexName matches SingleInstance.MutexName (Local\ namespace).
AppMutex=Photokompressor.Singleton
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
; On by default: the right-click menu is what this app is for. Also re-points the menu at
; the new location when upgrading from a zip install that lived somewhere else.
Name: "shellverb"; Description: "Add ""Compress with Photokompressor"" to the right-click menu of photos"
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
; The whole staged publish, minus the zip-only read-me (its advice about moving the
; folder by hand does not apply once an installer owns the location).
Source: "{#StageDir}\*"; DestDir: "{app}"; Excludes: "READ-ME-FIRST.txt,*.pdb"; \
    Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{userdesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
; The verb is defined once, in the app (ShellRegistration); the checkbox just calls it
; so the installer and the in-app toggle can never drift apart.
Filename: "{app}\{#AppExe}"; Parameters: "--register"; Tasks: shellverb; Flags: runhidden waituntilterminated
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Harmless if the verb was never registered - Unregister ignores missing keys.
Filename: "{app}\{#AppExe}"; Parameters: "--unregister"; Flags: runhidden; RunOnceId: "UnregShellVerb"

[Code]
var
  DownloadPage: TDownloadWizardPage;

function DotNetKeyHasV8(RootKey: Integer): Boolean;
var
  Names: TArrayOfString;
  I: Integer;
begin
  Result := False;
  if RegGetValueNames(RootKey,
    'SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App', Names) then
  begin
    for I := 0 to GetArrayLength(Names) - 1 do
      if Copy(Names[I], 1, 2) = '8.' then
      begin
        Result := True;
        Exit;
      end;
  end;
end;

function DotNetDesktop8Present: Boolean;
var
  FindRec: TFindRec;
begin
  Result := DotNetKeyHasV8(HKLM64) or DotNetKeyHasV8(HKLM32);
  if Result then
    Exit;
  // Fallback: the shared-framework folder itself.
  if FindFirst(ExpandConstant('{commonpf64}\dotnet\shared\Microsoft.WindowsDesktop.App\8.*'), FindRec) then
  begin
    try
      Result := True;
    finally
      FindClose(FindRec);
    end;
  end;
end;

procedure InitializeWizard;
begin
  DownloadPage := CreateDownloadPage(
    'Downloading the .NET 8 Desktop Runtime',
    'Photokompressor needs it and it is not installed yet. This is skipped if you already have it.',
    nil);
  DownloadPage.ShowBaseNameInsteadOfUrl := True;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  RuntimeExe: String;
  ResultCode: Integer;
begin
  Result := True;
  if (CurPageID <> wpReady) or DotNetDesktop8Present then
    Exit;

  RuntimeExe := ExpandConstant('{tmp}\windowsdesktop-runtime-8-win-x64.exe');
  if not FileExists(RuntimeExe) then
  begin
    DownloadPage.Clear;
    DownloadPage.Add('{#DotNetUrl}', 'windowsdesktop-runtime-8-win-x64.exe', '');
    DownloadPage.Show;
    try
      try
        DownloadPage.Download;
      except
        if DownloadPage.AbortedByUser then
          Log('Runtime download aborted by user.')
        else
          SuppressibleMsgBox(
            AddPeriod(GetExceptionMessage) + #13#10#13#10 +
            'You can install the .NET 8 Desktop Runtime (x64) yourself from ' +
            'https://dotnet.microsoft.com/download/dotnet/8.0 and run Setup again.',
            mbCriticalError, MB_OK, IDOK);
        Result := False;
        Exit;
      end;
    finally
      DownloadPage.Hide;
    end;
  end;

  if Exec(RuntimeExe, '/install /quiet /norestart', '', SW_SHOW, ewWaitUntilTerminated, ResultCode) then
  begin
    // 0 = installed, 3010 = installed, reboot pending, 1638 = same-or-newer already there.
    if (ResultCode <> 0) and (ResultCode <> 3010) and (ResultCode <> 1638) then
      SuppressibleMsgBox(
        Format('The .NET Desktop Runtime installer exited with code %d.'#13#10 +
               'Photokompressor may not start until the runtime is installed.', [ResultCode]),
        mbError, MB_OK, IDOK);
  end
  else
    SuppressibleMsgBox('Could not launch the downloaded .NET Desktop Runtime installer.',
      mbError, MB_OK, IDOK);
end;
