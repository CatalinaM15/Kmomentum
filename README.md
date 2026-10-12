# KMomentum

App nativa para iPhone (iOS 17+) con SwiftUI, SwiftData y widgets de inicio y bloqueo. Local, sin IA y sin servicios externos.

## Ejecutar y actualizar

Abre `KMomentum.xcodeproj`, selecciona **KMomentum** y tu iPhone o un simulador; pulsa ▶︎. Mantén los identificadores y el equipo de firma ya configurados al actualizar para conservar los datos. **No desinstales la app para actualizarla**: reinstálala desde Xcode sobre la existente.

Para otro equipo de desarrollo, configura la firma de ambos targets y el App Group `group.com.kmomentum.app`; si cambias el grupo, cambia los entitlements de app/widget y `Shared/WidgetSnapshot.swift`. HealthKit corresponde solo al target principal. Si el iPhone lo solicita, confía en tu certificado de desarrollo y activa el modo de desarrollador.

## Entrenamiento

- Cada ejercicio muestra series, repeticiones o duración y descanso.
- Tras iniciar, los ejercicios de fuerza permiten registrar peso (lb/kg) y repeticiones por serie. La unidad inicial se elige en **Ajustes → Entrenamiento → Unidad de peso**; las series guardadas conservan su propia unidad. El último registro del mismo ejercicio aparece como referencia. Los ejercicios por tiempo muestran su duración objetivo en formato mm:ss, sin campos de peso ni selector de unidades.
- La sesión guarda una copia de la rutina y el nombre del plan. Editar o activar otro plan no modifica una sesión iniciada ni el historial.
- El temporizador acumula solo tiempo activo, persiste al cerrar y permite pausar/reanudar. Si se deja corriendo, el tiempo en segundo plano cuenta.
- Terminar abre opciones de pausa, finalización, cancelación y continuación; avisa cuando queda tiempo estimado. Desde cinco minutos activos se puede completar como MVR.
- Cancelar requiere confirmación: conserva pesos y repeticiones como sesión incompleta, sin check. Para retomar una sesión se usa **Pausar**.
- Al cambiar de día, las sesiones abiertas del día anterior quedan incompletas. El tiempo se limita a la medianoche anterior, sin atribuir al día nuevo un entrenamiento antiguo.
- Todos los modos producen el mismo check y celebran con «¡Muy bien, mantuviste el momentum!», confeti y háptica. Ajustes permite desactivar cada efecto; se respeta Reducir movimiento.

Las nuevas series/repeticiones del plan base son valores iniciales editables. La fase menstrual conserva movimiento sin carga externa; MVR, recuperación e intermedio tienen sus propias adaptaciones.

## Planes guardados

En **Ajustes → Administrar planes** puedes editar el actual, crear desde la plantilla, duplicar, validar, previsualizar y guardar planes. **Guardar** no activa un plan nuevo. Solo hay un activo; el anterior permanece guardado. Puedes dejar todos sin seleccionar. El historial no se borra.

El editor permite copiar o pegar texto, muestra errores por campo/línea y compara bloques modificados con su versión anterior. **Versiones** recupera una versión en el editor; se valida y guarda antes de aplicarla.

La plantilla incluye los 39 bloques actuales (28 combinaciones fase/día, siete MVR, uno intermedio y tres etapas de recuperación). No hace falta escribirla de cero. Los bloques ausentes usan las adaptaciones base; esta regla se muestra al editar y validar. Los bloques específicos por fase tienen prioridad sobre los generales; después se prioriza día y etapa.

Ejemplo de un bloque:

```text
PLAN: Mi rutina
DÍA: Lunes
FASE: Todas
MODO: Estándar
TÍTULO: Fuerza controlada
MINUTOS: 40
NOTA: Ajusta la carga a cómo te sientes.

EJERCICIO: Sentadilla con mancuerna
SERIES: 3
REPETICIONES: 10
DESCANSO: 60
TÉCNICA: Evita bloquear las rodillas.

EJERCICIO: Plancha
SERIES: 3
DURACIÓN: 20
DESCANSO: 40
```

- `PLAN` aparece una vez al inicio. Cada `DÍA` inicia un bloque.
- `DÍA`: Lunes…Domingo o Todos. `FASE`: Menstrual, Folicular, Ovulatoria, Lútea o Todas.
- `MODO`: Estándar, Intermedio, MVR o Recuperación.
- `ETAPA`: opcional, solo Recuperación: 1 (días 1–3), 2 (4–7), 3 (8+).
- `MINUTOS`: tiempo orientativo de sesión. `DURACIÓN` y `DESCANSO`: segundos.
- Por ejercicio se exige `SERIES` y exactamente uno de `REPETICIONES` o `DURACIÓN`.
- `NOTA`, `TÉCNICA` y `DESCANSO` son opcionales. Si omites descanso, se usa cero.
- No se interpreta texto libre, PDF o Excel. No se usa inteligencia artificial.

## MVR y escalón intermedio

Tras tres días de calendario consecutivos completados en MVR aparece una revisión en tres pasos: sensaciones/ciclo y pulso manual opcional, fricción para entrenar y elección de MVR, recuperación o intermedio. Hay que responder, pero no se obliga a aumentar la carga. Se muestra una vez por racha, incluso al cerrar y abrir la app. Un día sin completar, completo, intermedio o recuperación rompe la racha. Un día nunca cuenta dos veces.

En Ajustes se puede registrar o quitar el pulso habitual; la revisión compara el dato manual de hoy con ese valor, sin usar un umbral de diagnóstico ni leer HealthKit. Elegir un modo al revisar un día ya completado prepara la próxima sesión y no cambia su check.

El intermedio propone 12 min de caminata y 8 min orientativos de fuerza: goblet a banco, 2×10 con 45 s de descanso; Pallof, 2×10 por lado con 30 s de descanso y 2 s de isometría. Al llegar a cinco minutos se puede cerrar como MVR. Se pueden probar dos días intermedios antes del completo, sin bloquearlo. En días 26–30 se recuerda que esta opción está disponible. La respiración nasal, velocidad o un valor de pulso no se presentan como garantías de seguridad.

## Apple Health

Solo se solicitan **flujo menstrual y pasos**. Se eliminó la consulta de frecuencia cardíaca, tanto instantánea como en reposo. Un permiso antiguo puede seguir visible en Ajustes de Salud, pero la app ya no consulta ese dato.

Los pasos de hoy usan una consulta estadística acumulada de HealthKit, se muestran con la hora de actualización y no condicionan el cumplimiento. Salud no permite distinguir permiso de lectura denegado de ausencia de datos: en ambos casos se muestra «Sin datos disponibles», no cero. La sincronización no es instantánea y depende de datos disponibles.

Las fases son una estimación de calendario de 30 días, no una confirmación de ovulación. Las correcciones manuales de periodo prevalecen sobre registros anteriores. Frases: «Lento pero constante», «Explota tu energía», «Fuerte y continúa» y «La constancia también puede ser suave».

## Widgets

- **Inicio mediano:** «Buen trabajo!» y círculos semanales cuando hoy está completado; antes de completar, solo una frase breve según la fase. Al tocar abre la sesión o los planes.
- **Inicio pequeño:** el mismo corazón semanal de la app, con fondo blanco, color por fase, porcentaje redondeado y conteo X/7. El llenado visual empieza en 40% al completar el primer día; el porcentaje representa los días reales sobre siete. Al tocar abre la sesión o los planes. La onda es estática en el widget; iOS controla su actualización.
- **Bloqueo rectangular:** sesión/duración o día completado; abre la sesión.
- **Bloqueo circular:** icono y minutos, o check, según espacio.
- Sin plan activo: «Selecciona un plan», abre Ajustes.

Se publica una previsión de ocho días a partir del plan y modo elegidos, que se renueva al abrir o modificar la app. El cambio a medianoche limpia el cumplimiento de hoy y actualiza el día de rutina. Pasado ese horizonte pide abrir la app, sin mostrar una rutina antigua como actual. iOS controla cuándo redibuja widgets. No se comparten pulso, pasos ni fecha del periodo con la extensión.

## Notificaciones y Atajos

En **Ajustes → Recordatorio diario fijo** puedes activar un aviso recurrente y elegir su hora (20:00 inicialmente). Se guarda en el perfil y se programa con un trigger local de hora/minuto que se repite diariamente, incluso después de completar una sesión. Al desactivarlo se cancela. Usa el copy: «Discipline is how you respect the life God trusted you with: Do Kmomentum -just 5 min».

Los recordatorios diarios siguen una matriz local de 28 días desde el inicio del periodo: menstrual (1–5) a las 11:00, folicular (6–13) a las 16:00, ovulatoria (14–16) a las 18:00 y lútea (17–28) a las 19:00. Alternan los dos copys de cada fase e insertan el día del ciclo donde aparece `[X]`. Sin fecha de periodo no se programan avisos por fase. Esta matriz de notificaciones usa 28 días; la estimación de fases de entrenamiento mantiene su calendario actual de 30 días.

Se programan siete días y se renuevan al abrir la app o corregir el periodo; completar el día cancela el aviso de hoy. El compromiso permite elegir una hora futura de hoy entre 04:00 y 23:30, con aviso a esa hora exacta. Se usan avisos time-sensitive, no alertas críticas. El App Shortcut abre MVR; iOS no ejecuta una automatización arbitraria por vencer una notificación.

## Verificación

```sh
bash Tests/run.sh
xcodebuild -project KMomentum.xcodeproj -scheme KMomentum -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/KMomentum-v2 CODE_SIGNING_ALLOWED=NO build
```

La suite prueba fases, exportación/importación del plan completo, errores de formato, prioridad y adaptaciones, tiempo activo/pausas, rachas de calendario con duplicados y cambios de horario. La prueba de SwiftData crea una base con los modelos originales y la abre con los nuevos: comprueba periodo, historial, preferencias, versiones, copia de rutina, pesos y sesiones canceladas.

Pendiente en iPhone físico: lectura de pasos reales, háptica, permisos de Salud y comportamiento de widgets con el App Group firmado. El simulador no puede validar sensaciones hápticas ni datos reales de Salud. Para distribución siguen pendientes icono de App Store y revisión del contenido de entrenamiento.


### Recordatorios persistentes y cierre compasivo

El recordatorio fijo (o el de fase si no hay uno fijo) inicia avisos cada cinco minutos. Abrir la app, tocar el recordatorio o ver/cerrar el menú no detiene la cola; los avisos se muestran también en primer plano. Se detienen al iniciar una sesión, completar o cerrar el día, o se reprograman al guardar una nueva hora. “Establecer como la nueva hora de hoy” abre el mismo selector de Ajustes y guarda un único compromiso global: cancela los avisos previos y confirma la nueva hora. Solo después de esa hora se habilitan “A descansar” y “Recovery”. El menú ocupa toda la pantalla y ofrece “Iniciar sesión” (Estándar), “MVR”, “Recovery” y “A descansar”. Las primeras dos opciones activan el modo elegido e inician la sesión; Recovery y descansar mantienen el cierre compasivo. Ambas opciones de descanso cierran el día con una cama y el texto “Descansa y respira. Mañana retomamos.”, sin confeti ni contar un entrenamiento. El widget mediano marca ese día en morado; Recovery guarda su número de día consecutivo en el historial. Una interrupción reinicia el conteo.

Límite de plataforma: la cola local tiene como máximo 64 solicitudes pendientes, incluyendo los avisos de días futuros, y permite el último aviso a medianoche (seis repeticiones para un compromiso a las 23:30). No es un bucle ilimitado con la app cerrada: cubre unas horas y se recalcula al abrir la app, cambiar preferencias o cambiar de día con la app activa. Los avisos de días futuros no pueden iniciar otra cola sin ejecutar la app. La vibración, el sonido y la entrega dependen de los ajustes de iOS. Al negociar o cerrar el día, el recordatorio fijo recurrente se sustituye por seis avisos futuros para silenciar hoy; la recurrencia se restaura en la siguiente actualización sin compromiso vigente.


### Siri, Atajos y estado del día (Milestone 11)

Los App Shortcuts se registran al iniciar la app. “Oye Siri, empezar KMomentum” abre la app y solicita iniciar la sesión del día o reanudar la que esté pausada. Usa el modo elegido para hoy; si ya completaste MVR, puede iniciar Estándar sin borrar ese éxito. Un día ya completado en Estándar o cerrado como descanso/Recovery no se reinicia. Los diálogos de finalización y revisión existentes se respetan.

“Cuál es mi progreso en KMomentum” devuelve un entero de 0 a 100 y Siri dice el porcentaje y la fracción semanal. Es el porcentaje mostrado en la app (1/7 = 14%), no la altura visual ponderada del líquido. Se consultan los registros guardados de la semana actual directamente en SwiftData, sin depender del widget ni abrir la interfaz.

En Atajos, añade **Consultar isSessionCompleted** y utiliza su resultado booleano en una acción **Si**. Devuelve `true` si hoy hay una sesión completada (incluido MVR) o se eligió Recovery; devuelve `false` para un día pendiente o solo descanso. Consulta el día local en cada ejecución y propaga los errores de lectura, sin convertirlos en un falso negativo. No se implementan bloqueos de otras apps.

Después de completar MVR y elegir descansar, al pie de la pantalla queda **¿Más energía? Iniciar Estándar**. Inicia una sesión Estándar nueva conservando el MVR y el día completado. El enlace desaparece cuando se completa Estándar o cambia el día, y puede recuperarse si se cancela el Estándar sin terminarlo.

Referencias: [App Intents](https://developer.apple.com/documentation/appintents/appintent), [registro de App Shortcuts](https://developer.apple.com/documentation/appintents/acceleratingappinteractionswithappintents). Pendiente: verificar reconocimiento de Siri, descubrimiento de acciones y automatizaciones reales en iPhone.
