; Instalador do App Vendas para Windows (Inno Setup 6).
; Gerado pelo GitHub Actions: iscc /DAppVersion=1.2.3 installer\app_vendas.iss
; Instala por usuário (sem pedir administrador), o que permite que o próprio
; app rode o instalador em modo silencioso para se atualizar.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{6F1C2A7E-4B3D-4E8A-9C21-7A5D0B3E9F42}
AppName=App Vendas
AppVersion={#AppVersion}
AppPublisher=thipain
AppPublisherURL=https://github.com/thipain/app_vendas
DefaultDirName={localappdata}\Programs\App Vendas
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=app_vendas-setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=force
RestartApplications=no
UninstallDisplayIcon={app}\app_vendas.exe
UninstallDisplayName=App Vendas

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\App Vendas"; Filename: "{app}\app_vendas.exe"
Name: "{autodesktop}\App Vendas"; Filename: "{app}\app_vendas.exe"; Tasks: desktopicon

[Run]
; Também roda na atualização silenciosa, reabrindo o app já atualizado.
Filename: "{app}\app_vendas.exe"; Description: "{cm:LaunchProgram,App Vendas}"; Flags: nowait postinstall
