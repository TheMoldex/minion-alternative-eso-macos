# ESO Addons for Mac — Alternativa a Minion para macOS

[English](README.md) · [Русский](README.ru.md) · [Français](README.fr.md) · [Español](README.es.md)

[![Build and tests](https://github.com/TheMoldex/minion-alternative-eso-macos/actions/workflows/build.yml/badge.svg)](https://github.com/TheMoldex/minion-alternative-eso-macos/actions/workflows/build.yml)

Gestor nativo de complementos de **The Elder Scrolls Online para macOS y Apple Silicon**, desarrollado con SwiftUI. Una alternativa independiente a Minion: catálogo ESOUI, actualizaciones automáticas, instalación de bibliotecas necesarias, capturas de pantalla y copias de los ajustes. Interfaz en inglés, ruso, francés y español.

**[Descargar para Mac](https://github.com/TheMoldex/minion-alternative-eso-macos/releases/latest/download/ESO-Addons-for-Mac.zip)** · [Versiones y sumas de verificación](https://github.com/TheMoldex/minion-alternative-eso-macos/releases) · [Comunicar un problema](https://github.com/TheMoldex/minion-alternative-eso-macos/issues)

## Instalación

Requisitos: **macOS 14 o posterior y Mac con Apple Silicon**. Esta versión no admite Mac con procesador Intel.

1. Abre la [última versión](https://github.com/TheMoldex/minion-alternative-eso-macos/releases/latest) y descarga **`ESO-Addons-for-Mac.zip`**. Los archivos automáticos «Source code» de GitHub contienen el código fuente, no la aplicación lista para usar.
2. Descomprime el ZIP, mueve **`ESO Addons for Mac.app`** a **Aplicaciones** y ábrela.
3. Permite el acceso a **Documentos** cuando macOS lo solicite: normalmente ahí se encuentran los complementos de ESO.
4. Comprueba la carpeta detectada. Si es otra, abre el engranaje → **General → Elegir carpeta…** y selecciona `live` o `AddOns`. La ruta habitual es `~/Documents/Elder Scrolls Online/live/AddOns`. Para el servidor de pruebas, selecciona `pts`.
5. Comprueba que tus complementos aparecen en **Instalados**. Después de instalar o actualizar, ejecuta **`/reloadui`** en ESO.

La aplicación está firmada localmente, sin certificado Apple Developer ID ni notarización. Si macOS bloquea el primer inicio y ofrece **Abrir igualmente**, la opción está en Ajustes del Sistema → Privacidad y seguridad. Consulta las [instrucciones de Apple](https://support.apple.com/es-es/102445). No necesitas una cuenta de desarrollador Apple ni un certificado personal para utilizar la aplicación.

## ¿Usabas Minion en macOS?

Selecciona la misma carpeta AddOns. La aplicación detecta los complementos existentes y puede utilizar los registros correspondientes de Minion para identificar su origen en ESOUI. No hace falta reinstalarlos todos ni mover SavedVariables. La configuración de Minion se lee sin modificarla. Cierra Minion antes de instalar o actualizar complementos aquí. Esta aplicación es independiente; no es una versión oficial de Minion ni un fork.

## Instalar, actualizar y eliminar

- **Instalados** muestra los complementos existentes y las etiquetas **Complemento / Biblioteca**. El estado distingue una actualización disponible, una versión actualizada, una versión local más reciente y una versión que no se pudo comprobar. Un estado desconocido no confirma que el complemento esté actualizado.
- **Buscar complementos** permite buscar por nombre, autor o carpeta en el catálogo ESOUI. Selecciona un complemento, pulsa **Instalar**, revisa la lista de complementos y bibliotecas propuestos y confirma.
- Las bibliotecas obligatorias y sus versiones mínimas se resuelven automáticamente. Las dependencias opcionales no se instalan automáticamente. Si no se puede identificar una biblioteca necesaria, la operación se detiene y lo indica.
- **Actualizaciones → Actualizar todo** presenta las actualizaciones reconocidas antes de cambiar los archivos. Una versión local más reciente no se sustituye automáticamente por una más antigua.
- La ficha muestra la descripción, las novedades y las capturas proporcionadas por ESOUI. Pulsa una miniatura para ampliarla; las flechas del teclado permiten recorrer las imágenes. Los textos de los autores no se traducen.
- Haz clic derecho en una fila para instalar, actualizar, reinstalar, ignorar actualizaciones, restablecer ajustes, abrir ESOUI o la carpeta y eliminar.
- Al eliminar, se muestran las carpetas afectadas. Se trasladan a la **Papelera de macOS**, sin crear una copia automática por eliminación. Puedes recuperarlas con **Sacar de la papelera**. SavedVariables permanece en su sitio. Las bibliotecas se conservan por defecto; la limpieza opcional solo incluye dependencias sin uso. Las bibliotecas que siguen utilizando otros complementos están protegidas.
- Después de modificar complementos, ejecuta **`/reloadui`** en el juego.

Combina los filtros de categoría, tipo y versión de ESO con la ordenación por nombre, descargas o última actualización. Restablecer filtros también borra la búsqueda. Los filtros limitan la lista visible; **Actualizar todo** sigue revisando las actualizaciones reconocidas, excepto las ignoradas.

El catálogo se guarda en caché durante una hora; las actualizaciones manuales del catálogo están limitadas a una por minuto. Si el origen de un complemento es ambiguo, selecciónalo y elige su origen ESOUI. Las actualizaciones en grupo no modifican carpetas cuyo origen no esté identificado.

## Ajustes y actualizaciones automáticas

Abre el engranaje de la parte inferior de la barra lateral o utiliza **⌘,**. **General** contiene las carpetas de ESO, el idioma y las opciones de copias. Los ajustes de actualizaciones incluyen la programación, las exclusiones, las descargas simultáneas y la comprobación de la versión de la aplicación. Selecciona **Español** para cambiar el idioma; la elección se conserva.

Arrastra los dos separadores verticales para cambiar el ancho de la barra lateral y la ficha. Los anchos se conservan después de reiniciar. Puedes guardar por separado las carpetas `live` y `pts`. Quitar una carpeta de la lista no borra archivos. Cada carpeta tiene sus propios orígenes, exclusiones, copias de actualización e historial.

Las actualizaciones automáticas están activadas por defecto y se comprueban cada hora mientras la aplicación está abierta. Solo afectan a los complementos reconocidos de la carpeta seleccionada. Se posponen si ESO o Minion está en ejecución, si hay una operación o confirmación abierta, mientras se muestran los ajustes o si la recuperación está bloqueada. Una pausa se reintenta a los cinco minutos; otros errores, a los quince.

**Ignorar actualizaciones** excluye un complemento de **Actualizar todo** y de las actualizaciones automáticas. Su botón individual sigue disponible. Las exclusiones se gestionan en los ajustes de actualizaciones. Si otro complemento necesita una versión más reciente de una biblioteca ignorada, la operación se detiene en lugar de actualizarla sin avisar.

Puedes elegir de 1 a 4 descargas simultáneas; el valor inicial es 3. Los archivos se descargan y verifican antes de instalar. Si falla la descarga o la comprobación de un archivo, se omite ese paquete. Los demás complementos se actualizan si sus bibliotecas necesarias están disponibles. El resultado indica los paquetes omitidos y el motivo.

Cerrar la ventana deja la aplicación en la barra de menús cuando las actualizaciones automáticas están activadas. Utiliza el menú de la aplicación para salir por completo. No hay servicio del sistema ni inicio automático después de reiniciar el Mac. El reposo suspende las comprobaciones. No ejecutes actualizaciones manuales en Minion y esta aplicación a la vez.

## Copias, transferencia y restauración

Hay dos clases de copias con funciones diferentes:

- **Copias para deshacer actualizaciones**: guardan las carpetas sustituidas durante instalaciones, actualizaciones y restauraciones. No incluyen los ajustes del juego ni SavedVariables. Puedes conservar todas o las últimas 5, 10 o 20; por defecto se conservan todas. Las copias necesarias para una recuperación pendiente están protegidas.
- **Ajustes y transferencia**: copias manuales de SavedVariables, `UserSettings.txt`, `AddOnSettings.txt`, el inventario de complementos y las asociaciones ESOUI. Incluir los archivos de los complementos permite transferirlos sin descargarlos otra vez. Sin esos archivos, el inventario por sí solo no los reinstala. Estas copias se conservan hasta que las elimines expresamente.

Para crear una copia manual o transferir a otro Mac:

1. Cierra **ESO y Minion**.
2. En los ajustes generales, elige una carpeta de copias fuera de `live` o `pts`.
3. Abre **Copias de seguridad → Ajustes y transferencia**. Puedes dar un nombre opcional a la copia e incluir los archivos de los complementos.
4. Pulsa **Crear copia manual**.
5. Para transferirla a otro Mac, copia la carpeta completa `ESO-Backup-…`, selecciona la carpeta ESO de destino, abre la copia desde la aplicación y revisa la lista antes de restaurar.

Solo se sustituyen los archivos y carpetas indicados; los demás elementos permanecen en su sitio. La transferencia no reescribe los identificadores de cuenta o personaje dentro de los ajustes. Los archivos se verifican con SHA-256. Desde 0.5.5, las copias automáticas para deshacer actualizaciones también contienen estas sumas. Las copias automáticas antiguas sin sumas se pueden consultar y eliminar, pero su botón de restauración está desactivado. Las copias manuales portátiles siguen siendo compatibles.

Selecciona varias copias con **⌘** o **⇧** y usa Eliminar o el menú contextual para moverlas a la Papelera. También puedes renombrar las copias manuales. La retención de copias de actualización no elimina las copias manuales.

**Restablecer ajustes…** es una acción separada. Muestra los archivos SavedVariables del complemento seleccionado y los mueve a la Papelera después de confirmar. Los ajustes compartidos están protegidos. Cierra ESO antes para evitar que vuelva a escribir sus ajustes anteriores al salir.

## Archivos y diagnóstico

Las instalaciones, actualizaciones y eliminaciones ordinarias conservan los ajustes del juego y SavedVariables. Solo una restauración manual o un restablecimiento explícito de ajustes los modifica. Las tablas de precios TTC existentes se conservan al actualizar Tamriel Trade Centre; para sincronizar TTC utiliza el [cliente TTC separado](https://github.com/TheMoldex/ttc-client-macos).

Las descargas usan HTTPS y servidores ESOUI/MMOUI permitidos. Se comprueban el MD5 del archivo y los CRC del ZIP para detectar corrupción; no constituyen una firma del autor. Se rechazan rutas peligrosas, enlaces y tamaños de descompresión excesivos.

Las carpetas de solo lectura que pertenecen a tu cuenta pueden recibir permiso de escritura para su propietario antes de sustituirlas. Los archivos bloqueados en Finder se rechazan antes de iniciar los cambios. Restaurar una biblioteca no puede romper una dependencia que funcionaba en un complemento conservado. La recuperación pendiente espera a que se cierren ESO y Minion.

Si un archivo no se puede leer o falla la recuperación, la lista de complementos sigue visible y los cambios quedan bloqueados. El mensaje indica la ruta afectada. Corrige los permisos o los datos señalados y vuelve a comprobar. El historial conserva las últimas 500 entradas de la carpeta seleccionada y permite filtrar errores. Antes de compartir registros, elimina nombres de cuenta, rutas privadas y contenido de SavedVariables.

Los datos de la aplicación se guardan en `~/Library/Application Support/ESOAddonsMac/` y las preferencias en `local.denstash.ESOAddonsMac`. El archivo oculto `.eso-addons.lock` impide operaciones simultáneas de esta aplicación sobre la misma carpeta. Nunca se modifica la configuración de Minion.

## Actualizar la aplicación

La versión se comprueba en GitHub al iniciar y después cada hora. Se ofrece una versión estable más reciente cuando incluye el ZIP de la aplicación; se omiten borradores y versiones preliminares. Al posponer, queda una indicación en la barra lateral. También puedes comprobar manualmente desde los ajustes de actualizaciones y los menús.

Para instalar una nueva versión, descarga el ZIP de la [última publicación](https://github.com/TheMoldex/minion-alternative-eso-macos/releases/latest), sal de la aplicación y sustitúyela en Aplicaciones. La instalación de actualizaciones es manual. No se envían a GitHub credenciales de ESO ni archivos del juego.

Las antiguas versiones locales hasta 0.5.5 utilizan el repositorio anterior: instala **0.5.6** manualmente una vez para empezar a recibir las publicaciones de `TheMoldex/minion-alternative-eso-macos`.

## Compilar y comprobar

Se necesitan Xcode Command Line Tools. No se requieren paquetes Swift externos ni Java.

```sh
./build.sh /tmp/ESOAddons.app
```

La compilación ejecuta las comprobaciones locales. Para probar además descargas reales de ESOUI, instalaciones, copias, restauraciones y recuperación dentro de carpetas temporales:

```sh
ESO_LIVE_TESTS=1 ./build.sh /tmp/ESOAddons.app
```

La firma es local por defecto. Puedes indicar un certificado de firma existente mediante `ESO_SIGNING_IDENTITY`; el script no crea ni importa certificados. Sustituir una compilación puede provocar otra solicitud de acceso a Documentos. Reiniciar la misma compilación no cambia su firma. El distintivo de la parte superior muestra las comprobaciones de GitHub Actions. No se han probado todos los ZIP del catálogo ESOUI ni la instalación en otro Mac.

Aplicación independiente y no oficial, sin relación con ESOUI, MMOUI, Minion, ZeniMax ni Bethesda. Los complementos pertenecen a sus autores y se descargan desde ESOUI cuando lo solicita el usuario. Para obtener ayuda, abre una [incidencia en GitHub](https://github.com/TheMoldex/minion-alternative-eso-macos/issues) con la versión de la aplicación, la versión de macOS y los pasos para reproducir el problema.
