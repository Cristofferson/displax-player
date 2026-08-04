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

[Messages]
; La pagina de tareas es donde se confunde la gente: da por hecho que la casilla
; del salvapantallas es OTRA forma de instalar, y que al marcarla no deberia
; quedar tambien un player normal. No es asi, y el texto de arriba de la lista es
; el unico lugar donde se puede decir antes de que marque nada.
;
; El texto va en espanol para los dos idiomas, igual que las descripciones de
; [Tasks]: el instalador se usa en tienda y ese es el idioma de quien lo corre.
SelectTasksLabel2=Se instala siempre el player completo. Estas casillas no eligen QUE se instala, sino CUANDO se ve el contenido: el salvapantallas es el mismo programa, no una instalacion aparte. Puede marcar las dos, una o ninguna.

[Tasks]
; Ninguna de estas casillas cambia lo que se instala: el player completo se copia
; siempre. DISPLAX.scr es el MISMO binario con el bit de salvapantallas puesto (lo
; produce el post-build con un xcopy del .exe), asi que una instalacion "solo
; salvapantallas" no existe: el .scr necesita los ~310 archivos del player a su
; lado. Lo unico que se elige aqui es CUANDO aparece el contenido en pantalla, y
; las dos casillas son independientes: marcar las dos deja las dos puestas.
;
; Van seguidas y con el MISMO GroupDescription a proposito. Meter otra tarea en
; medio (el acceso directo, por ejemplo) hace que Inno repita el encabezado del
; grupo y parezca que son dos apartados distintos.
Name: "autoarranque"; Description: "Todo el tiempo: iniciar el player al encender el equipo (pantalla dedicada)"; GroupDescription: "Cuando debe verse el contenido. El player se instala igual en los dos casos:"
; Se registra por ruta completa y NO copiandolo a System32: ahi no encontraria los
; ~310 archivos que necesita a su lado.
; Los 3 minutos los fija el valor por omision de TimeoutSeconds en el script:
; si cambia alla, esta leyenda tiene que cambiar aqui.
Name: "salvapantallas"; Description: "Solo en reposo: mostrarlo como salvapantallas tras 3 minutos sin actividad (equipo que ademas se usa para trabajar)"; GroupDescription: "Cuando debe verse el contenido. El player se instala igual en los dos casos:"; Flags: unchecked
Name: "escritorio"; Description: "Crear acceso directo en el escritorio"; GroupDescription: "Accesos directos:"; Flags: unchecked

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
;
; Solo toca el registro. Puede correr aqui, antes de que nadie haya capturado el
; CMS, porque el salvapantallas ya NO tiene ajustes propios que llenar: comparte
; el archivo del player (ApplicationSettings.cs nombra los ajustes con el nombre
; del ENSAMBLADO, que no cambia al copiar el .exe a DISPLAX.scr).
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\tools\Install-Screensaver.ps1"" -AllUsers"; \
  StatusMsg: "Registrando el salvapantallas..."; \
  Flags: runhidden waituntilterminated; Tasks: salvapantallas

; En una pantalla nueva no hay ajustes que migrar y el player arranca sin registrar:
; una pantalla en negro que parece un cuelgue. Por eso la primera casilla es la de
; configurar el CMS, y viene marcada. Sirve para los dos modos: lo que se capture
; aqui es lo que usa tambien el salvapantallas.
Filename: "{app}\{#AppExeName}"; Parameters: "o"; \
  Description: "Configurar la direccion del CMS y la llave ahora (sirve para los dos modos)"; \
  Flags: nowait postinstall skipifsilent

; No se ofrece en una instalacion de SOLO salvapantallas, y no es por limpieza:
; abrir el player en modo normal arranca el watchdog, que a partir de ahi revive
; DisplaxPlayer.exe cada 60 segundos cada vez que no lo encuentra corriendo
; (Watcher.cs) y no se entera de que la pantalla se cierra a proposito. En una
; maquina donde el player solo debe verse como protector, esa casilla dejaba un
; player reapareciendo solo cada minuto hasta reiniciar.
;
; El watchdog en si esta bien como esta: en una pantalla dedicada es justo lo que
; se quiere, y el comando SoftRestart del CMS DEPENDE de el para volver a levantar
; el player. Por eso se corta aqui, en quien lo dispara, y no en el player.
Filename: "{app}\{#AppExeName}"; Description: "Iniciar DISPLAX Player ahora"; \
  Flags: nowait postinstall skipifsilent unchecked; Check: EsPantallaDePlayer

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

; [Code] va al final a proposito: Inno exige que sea la ultima seccion del script.
; Ojo con los comentarios aqui dentro, que son Pascal y no del formato .iss: se
; escriben con // y un ; al inicio de linea es un error de compilacion.
[Code]
// Cierto salvo en la instalacion de SOLO salvapantallas, que es la unica donde
// abrir el player en modo normal no es lo que la pantalla va a hacer nunca.
function EsPantallaDePlayer: Boolean;
begin
  Result := WizardIsTaskSelected('autoarranque') or not WizardIsTaskSelected('salvapantallas');
end;
