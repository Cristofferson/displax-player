; Instalador del DISPLAX Player.
;
; El player son ~310 archivos y ~350 MB (CefSharp incluye un Chromium completo),
; asi que copiarlo a mano a cada tienda no es una opcion. Este script los empaqueta
; en un solo ejecutable y, sobre todo, se encarga de las dos cosas que el
; rebrandeo rompe si nadie las atiende: los ajustes que viven en un archivo
; nombrado como el .exe, y la carpeta de biblioteca nombrada como el producto.
;
; Se compila con Inno Setup 6:
;     iscc installer\displax-player.iss
; La CI lo hace en cada push; ver .github/workflows/build.yml

#define AppName        "DISPLAX Player"
#define AppPublisher   "XUBAX"
#define AppExeName     "DisplaxPlayer.exe"
#define AppUrl         "https://displax.xubax.com"

; La CI inyecta la version real con /DAppVersion=...; este es el respaldo
; para una compilacion manual desde un escritorio.
#ifndef AppVersion
  #define AppVersion "4.407.0"
#endif

; Carpeta con la salida de la compilacion. La CI la pasa con /DPayloadDir=...
#ifndef PayloadDir
  #define PayloadDir "..\bin\Release"
#endif

[Setup]
AppId={{8F3C21A6-5D74-4E92-9C1B-DIS0PLAX0001}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
DefaultDirName={commonpf32}\DISPLAX Player
DefaultGroupName={#AppName}
OutputDir=..\dist
OutputBaseFilename=DISPLAX-Player-Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; El player es de 32 bits (PlatformTarget AnyCPU con Prefer32Bit en x86), y el
; watchdog se busca en Program Files (x86). Instalar en la vista de 32 bits
; mantiene ambos donde el codigo los espera.
ArchitecturesInstallIn64BitMode=
PrivilegesRequired=admin
; Una pantalla de tienda se actualiza en remoto y sin nadie delante: que el
; instalador pueda correr desatendido con /VERYSILENT no es un lujo.
CloseApplications=yes
RestartApplications=no
SetupIconFile=..\new-icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
; La AGPLv3 obliga a que quien recibe el binario sepa que es software libre y
; pueda llegar al codigo. El instalador lo dice antes de instalar.
LicenseFile=..\LICENSE
InfoBeforeFile=aviso-agpl.txt

[Languages]
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "autoarranque"; Description: "Iniciar DISPLAX Player al encender el equipo"; GroupDescription: "Operacion desatendida:"
Name: "escritorio"; Description: "Crear acceso directo en el escritorio"; Flags: unchecked
; La compilacion ya trae DISPLAX.scr, que es el mismo binario con el bit de
; salvapantallas puesto. Se registra por ruta completa y NO copiandolo a System32:
; ahi no encontraria los ~310 archivos que necesita a su lado.
Name: "salvapantallas"; Description: "Usar el player como salvapantallas a los 10 minutos sin actividad"; GroupDescription: "Operacion desatendida:"; Flags: unchecked

[Files]
Source: "{#PayloadDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; El script de migracion viaja con el instalador para poder relanzarlo a mano
; si algo sale raro y hay que revisar con -WhatIf antes de repetir.
Source: "..\tools\Migrate-FromXibo.ps1"; DestDir: "{app}\tools"; Flags: ignoreversion
; Tambien viaja suelto para poder activar o quitar el salvapantallas despues, sin
; reinstalar, en las maquinas donde se decida mas tarde.
Source: "..\tools\Install-Screensaver.ps1"; DestDir: "{app}\tools"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
; El argumento va SIN guion: App.xaml.cs compara contra la cadena "o" pelada, y
; cualquier otra forma cae en el caso por omision, que arranca el player como
; salvapantallas y se cierra al primer movimiento del mouse: parece que el acceso
; directo no hace nada.
Name: "{group}\Opciones de DISPLAX Player"; Filename: "{app}\{#AppExeName}"; Parameters: "o"
Name: "{commondesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: escritorio
Name: "{commonstartup}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: autoarranque

[Run]
; La migracion corre ANTES del primer arranque y en el contexto del usuario que
; va a ejecutar el player, no en el del administrador que lanza el instalador:
; los ajustes y la biblioteca viven en el perfil de ese usuario.
;
; Sin este paso el player arranca SIN REGISTRAR (pierde la direccion del CMS, la
; llave y su identidad, porque los ajustes se guardan en
; %APPDATA%\<nombre-del-exe>.xml) y ademas vuelve a descargar su biblioteca
; entera, dejando la pantalla en blanco hasta terminar.
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\tools\Migrate-FromXibo.ps1"" -AllUsers"; \
  StatusMsg: "Migrando ajustes y biblioteca desde la instalacion anterior..."; \
  Flags: runhidden waituntilterminated

; El ajuste del salvapantallas es POR USUARIO, asi que corre con -AllUsers por la
; misma razon que la migracion: quien instala es un administrador y quien mira la
; pantalla no.
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\tools\Install-Screensaver.ps1"" -AllUsers"; \
  StatusMsg: "Registrando el salvapantallas..."; \
  Flags: runhidden waituntilterminated; Tasks: salvapantallas

; En una pantalla nueva no hay ajustes que migrar y el player arranca sin registrar:
; una pantalla en negro que parece un cuelgue. Por eso la primera casilla es la de
; configurar el CMS, y viene marcada.
Filename: "{app}\{#AppExeName}"; Parameters: "o"; \
  Description: "Configurar la direccion del CMS y la llave ahora"; \
  Flags: nowait postinstall skipifsilent

Filename: "{app}\{#AppExeName}"; Description: "Iniciar DISPLAX Player ahora"; \
  Flags: nowait postinstall skipifsilent unchecked

[UninstallRun]
; Si se registro el salvapantallas hay que soltarlo antes de borrar los archivos,
; o Windows queda apuntando a un .scr que ya no existe. Corre siempre, no solo
; cuando la tarea estuvo marcada: quitarlo cuando no estaba puesto no hace nada.
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\tools\Install-Screensaver.ps1"" -Remove -AllUsers"; \
  StatusMsg: "Quitando el salvapantallas..."; \
  Flags: runhidden waituntilterminated; RunOnceId: "QuitarSalvapantallas"

[UninstallDelete]
; Se borra lo que el instalador puso, nunca la biblioteca ni los ajustes: un
; desinstalar-reinstalar no debe costarle a la tienda una redescarga completa ni
; volver a dar de alta la pantalla en el CMS.
Type: filesandordirs; Name: "{app}\tools"
