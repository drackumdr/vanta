# Especificación Técnica: Cifrado de Flujo de Hikvision (Stream Encryption)

Esta especificación documenta la ingeniería inversa del mecanismo de cifrado de flujo de video empleado por grabadores **Hikvision, Epcom y Hilook** en su plataforma **Hik-Connect / EZVIZ**, validada directamente contra hardware real (DVR modelo **S08-TURBO-M1**, firmware `V4.71.411`).

---

## 1. Fundamentos Criptográficos

| Parámetro | Valor |
| :--- | :--- |
| **Algoritmo** | **AES-128-ECB** (Advanced Encryption Standard, 128 bits, Electronic Codebook) |
| **Tamaño de Bloque** | 16 bytes (128 bits) |
| **Modo de Relleno** | Sin relleno en bloques completos; zero-padding / truncado según el NALU |
| **Entrada de Usuario** | Código de verificación de 6 caracteres alfanuméricos (ej. `DVRDTK`) |
| **Derivación de Clave** | **Zero-Padding a 16 bytes:** el string ASCII se copia en los primeros bytes y se rellena con `0x00` hasta completar los 16 bytes. |

### Representación de la Clave
Para el código de verificación `DVRDTK`:
```text
ASCII:  D    V    R    D    T    K   \0   \0   \0   \0   \0   \0   \0   \0   \0   \0
HEX:   0x44 0x56 0x52 0x44 0x54 0x4B 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00
```

---

## 2. Estructura de Empaquetado en NALUs H.264

Al analizar y comparar los streams capturados por RTSP con cifrado activo vs sin cifrar:

### A. Sequence Parameter Set (SPS - NALU Tipo 7)
- En el flujo cifrado, el bloque de parámetros del SPS es sustituido por un bloque cifrado de 16 bytes.
- Al aplicar **AES-128-ECB** con la clave `ZeroPadding(verificationCode)` sobre el bloque cifrado:
  ```text
  Cifrado:    a0 0b a2 46 6c 11 49 da 17 c0 06 df 83 f0 87 4e
  Descifrado: 67 64 00 20 ac 1b 1a 80 f0 08 9a 10 00 00 bb 80
  ```
  El resultado produce **exactamente** la cabecera `0x67` (SPS, refIdc=3) y los parámetros originales (`Profile High 0x64`, `Level 3.2 0x20`), coincidiendo al 100% con el SPS del flujo sin cifrar.

### B. Picture Parameter Set (PPS - NALU Tipo 8)
- **El PPS no se cifra.** Viaja en texto plano en ambos flujos (`68 ee 3c b0`), preservando los parámetros de cuantización y codificación de entropía (CABAC/CAVLC).

### C. Slices de Video (IDR Tipo 5 y Non-IDR P/B Tipo 1)
- Las cabeceras del slice (`first_mb_in_slice`, `slice_type`, `pic_parameter_set_id`, `frame_num`) viajan en claro (aproximadamente los primeros 8-9 bytes).
- Los datos comprimidos de los macrobloques residuales y vectores de movimiento se cifran en bloques AES de 16 bytes.

---

## 3. Arquitectura del Micro-Proxy VANTA

Para reproducir streams con cifrado activo sin utilizar el SDK oficial de Hikvision:

```
[ NVR / DVR Hikvision ]
         │
         │  RTSP cifrado (puerto 554)
         ▼
[ VantaDecryptionProxy ] (Loopback en 127.0.0.1)
         │  1. Cliente RTSP interno (intercepción RTP)
         │  2. AES-128-ECB con ZeroPadding(verificationCode)
         │  3. Remuxing RTP/H.264 limpio
         ▼
[ media_kit / Media3 ] (Aceleración por GPU)
```

### Ventajas Comprobadas:
1. **Multiplataforma garantizada:** Funciona en Windows, Linux, Android y Android TV con exactamente el mismo algoritmo.
2. **Cero dependencias pesadas:** No requiere las 40 DLLs/SOs del SDK oficial (+100 MB).
3. **Compatible con la UI de VANTA:** No interfiere con `TvFocusable`, atajos D-Pad ni aceleración por hardware.
