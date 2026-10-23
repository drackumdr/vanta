# ISAPI y Fuentes de Video

Este documento resume cómo VANTA se comunica con un DVR/NVR Hikvision y cómo
separa las consultas ISAPI de las fuentes de video RTSP.

## Arquitectura General

VANTA usa dos canales de comunicación distintos:

1. **ISAPI sobre HTTP/HTTPS**: identifica el equipo, consulta hora y canales,
   obtiene snapshots y busca grabaciones.
2. **RTSP**: transporta el video en vivo y la reproducción de grabaciones.

ISAPI no transporta el video principal de la aplicación. El cliente HTTP vive
en `lib/services/isapi_client.dart`; las operaciones de videovigilancia están
en `lib/services/hikvision_service.dart`; las URLs RTSP se construyen en
`lib/services/rtsp_url_builder.dart`.

## Conexión ISAPI

Cada dispositivo contiene:

- Host o dirección IP.
- Puerto HTTP/HTTPS, normalmente `80`.
- Puerto RTSP, normalmente `554`.
- Usuario y contraseña.
- Indicador de HTTPS.

La URL base se construye así:

```text
http://HOST:PUERTO
https://HOST:PUERTO
```

El timeout predeterminado es de 8 segundos.

### Autenticación Digest

`IsapiClient` implementa autenticación HTTP Digest con `qop=auth`:

1. Envía la petición sin autenticación.
2. El dispositivo responde `401` con `WWW-Authenticate: Digest ...`.
3. Extrae `realm`, `nonce`, `qop` y opcionalmente `opaque`.
4. Genera un `cnonce` aleatorio y un contador `nc`.
5. Calcula:

```text
HA1 = MD5(usuario:realm:contraseña)
HA2 = MD5(método:ruta[?query])
response = MD5(HA1:nonce:nc:cnonce:qop:HA2)
```

6. Repite la misma petición con el encabezado `Authorization: Digest ...`.

Las peticiones XML con cuerpo usan `Content-Type: application/xml; charset=UTF-8`.
Las peticiones GET sin cuerpo no envían `Content-Type`, porque algunos
firmwares NVR rechazan un GET con `application/json` o XML inválido. Las
respuestas binarias, como snapshots, usan `Accept: */*`.

### Respuestas y errores

Las respuestas ISAPI se reciben como `http.Response`:

- `response.body`: XML o texto.
- `response.bodyBytes`: datos binarios, por ejemplo JPEG.
- `statusCode`: resultado HTTP.

Los códigos se convierten en `IsapiException` y `ApiErrorKind`:

| Código | Resultado |
|---|---|
| `200`, `202` | Operación correcta |
| `401` | Usuario o contraseña incorrectos |
| `403` | Operación no permitida |
| `404`, `405` | Función no soportada |
| `408` | Timeout |
| `500`, `502`, `503` | Error del dispositivo |
| Sin conexión | Dispositivo inaccesible |

## Peticiones ISAPI

### Información del dispositivo

```http
GET /ISAPI/System/deviceInfo
```

La respuesta es XML. VANTA extrae `deviceName`, `model`, `serialNumber`,
`firmwareVersion` y `macAddress`.

### Canales (DVR vs NVR)

VANTA implementa un descubrimiento de canales en cascada para soportar tanto DVRs analógicos como NVRs puros:

1. **Canales analógicos (DVR / híbrido)**:
   ```http
   GET /ISAPI/System/Video/inputs/channels
   ```
   Retorna elementos `VideoInputChannel` con `id`, `name`, `videoInputEnabled` y `resDesc`.

2. **Canales IP Proxy (NVR como DS-7616NI)**:
   Los NVRs puros no tienen entradas analógicas y devuelven `notSupport` al endpoint anterior. Sus cámaras se obtienen en:
   ```http
   GET /ISAPI/ContentMgmt/InputProxy/channels
   ```
   Retorna elementos `InputProxyChannel` con `id`, `name` y `sourceInputPortDescriptor` (`ipAddress`, `model`, etc.). Si el nombre devuelto es genérico (e.g. `Camera 01`), se enriquece automáticamente como `CH{id} · {modelo}`.

3. **Fallback universal**:
   ```http
   GET /ISAPI/Streaming/channels
   ```
   Si los anteriores no están disponibles, infiere los canales y resoluciones a partir de los `StreamingChannel`.

### Hora del dispositivo

```http
GET /ISAPI/System/time
```

La respuesta XML puede incluir `localTime` y `timeZone`. VANTA obtiene el
offset UTC desde el sufijo de `localTime` o desde `timeZone`.

El offset se almacena en una caché estática por dispositivo. Esto es importante
porque las búsquedas CMS esperan las fechas en la hora local del grabador,
mientras que los resultados de grabación se interpretan como UTC.

### Snapshot

```http
GET /ISAPI/Streaming/channels/{canal}01/picture
GET /ISAPI/Streaming/channels/{canal}02/picture
```

`01` identifica el stream principal y `02` el substream. La respuesta debe ser
un JPEG: VANTA valida que tenga al menos 1024 bytes y los bytes iniciales
`FF D8`.

## Búsqueda de Grabaciones

La búsqueda usa el endpoint CMS:

```http
POST /ISAPI/ContentMgmt/search
Content-Type: application/xml; charset=UTF-8
```

El cuerpo enviado tiene esta forma:

```xml
<CMSearchDescription>
  <searchID>UUID</searchID>
  <trackList>
    <trackID>101</trackID>
  </trackList>
  <timeSpanList>
    <timeSpan>
      <startTime>2026-09-11T00:00:00-06:00</startTime>
      <endTime>2026-09-11T23:59:59-06:00</endTime>
    </timeSpan>
  </timeSpanList>
  <maxResults>300</maxResults>
  <searchResultPostion>0</searchResultPostion>
  <metadataList>
    <metadataDescriptor>//recordType.meta.std-cgi.com</metadataDescriptor>
  </metadataList>
</CMSearchDescription>
```

El `trackID` se forma como `{canal}01`; por ejemplo, el canal 1 usa `101`.
La búsqueda de grabaciones utiliza el stream principal como pista de archivo,
independientemente de que el grid esté mostrando el substream.

La respuesta XML debe contener:

```xml
<responseStatus>true</responseStatus>
<searchMatchItem>
  <trackID>101</trackID>
  <timeSpan>
    <startTime>...</startTime>
    <endTime>...</endTime>
  </timeSpan>
  <mediaSegmentDescriptor>
    <contentType>...</contentType>
    <codecType>...</codecType>
    <playbackURI>...</playbackURI>
  </mediaSegmentDescriptor>
  <metadataMatches>
    <metadataDescriptor>recordType.meta.hikvision.com/timing</metadataDescriptor>
  </metadataMatches>
</searchMatchItem>
```

Cada `searchMatchItem` válido se convierte en un `RecordingSegment` con:

- `trackId`.
- `startUtc` y `endUtc`.
- `contentType` y `codecType`.
- `playbackUri`.
- Nombre o descriptor de metadata.

Los segmentos se ordenan por hora inicial.

## Cómo Identifica Días Con Grabaciones

El calendario no recibe una lista mensual directa del DVR. VANTA determina
los días mediante consultas pequeñas:

1. Carga la hora y offset del dispositivo.
2. Toma el mes visible y calcula cuántos días tiene.
3. Para cada día pasado o actual, consulta `POST /ISAPI/ContentMgmt/search`.
4. Usa un intervalo desde `00:00:00` hasta `23:59:59` del día local del DVR.
5. Usa `maxResults=1`, porque solo necesita saber si existe al menos un
   segmento.
6. Marca el día como disponible si la respuesta contiene algún
   `searchMatchItem`.
7. Los días futuros se marcan directamente como sin grabación.

Las consultas se ejecutan en lotes de cinco para no saturar el DVR. Los
resultados se guardan por clave `AAAA-MM`, evitando repetir la consulta cuando
el usuario vuelve al mismo mes.

Al seleccionar un día, VANTA ejecuta una búsqueda completa con
`maxResults=300`, carga los segmentos y los dibuja sobre una timeline de 24
horas. Al tocar una zona con grabación se selecciona el segmento correspondiente.

## Timeline y Reproducción Profesional

Los timestamps devueltos por el endpoint CMSearch de Hikvision (`startTime`,
`endTime`, `playbackURI`) reflejan directamente el reloj local del dispositivo,
incluso cuando el firmware anexa un sufijo `Z` o un offset. VANTA los interpreta
directamente como hora local del dispositivo para evitar desfases dobles de zona
horaria.

La posición horizontal sobre la timeline de 24 horas se calcula relativa al inicio
del día seleccionado (`00:00:00`):

```text
x = anchoTimeline * clamp(segundosDesdeMedianoche, 0, 86400) / 86400
```

Los segmentos que cruzan la medianoche (por ejemplo, de 23:54 de ayer a 01:39 de hoy)
se acotan automáticamente a la ventana visible del día (`00:00:00` a `23:59:59`),
asegurando que la aguja y los bloques se ubiquen con precisión.

### Arquitectura del Reproductor Multicámara

El reproductor profesional de VANTA integra múltiples componentes en un solo espacio de trabajo:

1. **Panel lateral izquierdo**:
   - **Selector de cámaras** (arriba): Permite seleccionar hasta 4 cámaras simultáneamente con casillas de verificación y etiquetas de color distintivas por pista.
   - **Selector de fecha / Calendario** (abajo): Muestra el mes consultado con indicadores verdes en los días que contienen grabaciones para las cámaras seleccionadas.
2. **Área central de video**:
   - Cuadrícula de video sincronizada (1x1 o 2x2 para hasta 4 cámaras activas a la vez).
   - Barra de controles con Reproducir, Pausar, Detener, Silenciar/Audio y visualizador del cursor horario (`HH:mm:ss`).
3. **Línea de tiempo arrastrable (*scrubbing*)**:
   - Posicionada abajo del video a lo largo de las 24 horas del día.
   - Pistas independientes por cámara activa, diferenciando eventos continuos y alarmas/movimiento.
   - Cabezal/aguja de tiempo interactiva que se puede arrastrar horizontalmente para saltar de forma instantánea a cualquier segundo del día en todas las cámaras activas.

Para reproducir un instante:

1. Al mover o soltar el cabezal en un timestamp `T`, se calcula la hora local del dispositivo.
2. Para cada cámara seleccionada que tenga grabación en ese momento, se resuelve su URL de playback (usando `playbackURI` adaptado o la plantilla `tracks/{canal}01?starttime=...&endtime=...`).
3. Se abre o actualiza la sesión con `VideoSink`.

## Fuentes RTSP En Vivo

Las URLs en vivo siguen el patrón Hikvision:

```text
rtsp://usuario:contraseña@HOST:554/Streaming/Channels/{canal}01
rtsp://usuario:contraseña@HOST:554/Streaming/Channels/{canal}02
```

- Sufijo `01`: stream principal.
- Sufijo `02`: substream.

Ejemplo:

```text
rtsp://admin:contraseña@192.168.1.24:554/Streaming/Channels/101
```

`StreamManager` mantiene una sesión por cámara visible, reutiliza sesiones
cuando la URL no cambia, cierra cámaras que dejan de estar visibles y reintenta
errores con backoff exponencial, jitter y un máximo de 12 intentos.

## Motores de Video

### Android e iOS

`RtspSession` usa el plugin nativo `vanta/rtsp`:

- Android: Media3/ExoPlayer.
- Renderizado: textura Flutter.
- Estados: `idle`, `loading`, `ready`, `ended`, `error`.

### Windows y Linux

`DesktopVideoSession` usa `media_kit` y libmpv:

- Un `Player` por cámara visible.
- `MediaKit.ensureInitialized()` al iniciar desktop.
- `VideoController` para renderizar.
- Detección de resolución y relación de aspecto por stream.
- Reconexión administrada por `StreamManager`.

Ambos motores implementan el contrato común `VideoSink`, por lo que ISAPI,
calendario, búsqueda y construcción de URLs no dependen de la plataforma de
renderizado.

## Flujo Completo

```text
Dispositivo guardado
        |
        v
GET /ISAPI/System/deviceInfo  --> identificación
GET /ISAPI/System/time        --> offset horario
GET /ISAPI/.../channels       --> canales
        |
        +--> RTSP Channels/{ch}01|02 --> video en vivo
        |
        +--> POST /ISAPI/ContentMgmt/search
                    |
                    +--> días con grabaciones
                    +--> segmentos del día
                    +--> playbackURI / RTSP tracks/{ch}01
```

## Archivos Clave

- `lib/services/isapi_client.dart`: HTTP, Digest, timeouts y errores.
- `lib/services/hikvision_service.dart`: endpoints ISAPI y XML.
- `lib/services/rtsp_url_builder.dart`: URLs live/playback.
- `lib/services/stream_manager.dart`: sesiones visibles y reconexión.
- `lib/models/recording_models.dart`: segmentos y canales.
- `lib/ui/recordings/recordings_page.dart`: estación de trabajo de reproducción profesional, selector de cámaras, calendario y controles.
- `lib/ui/recordings/playback_page.dart`: visor de reproducción individual a pantalla completa.
- `lib/ui/recordings/timeline_widget.dart`: timeline interactiva arrastrable con soporte multipista de 24 horas.
- `lib/video/video_sink.dart`: contrato multiplataforma.
- `lib/video/rtsp_session.dart`: Media3/ExoPlayer.
- `lib/video/desktop_session.dart`: media_kit/libmpv.
