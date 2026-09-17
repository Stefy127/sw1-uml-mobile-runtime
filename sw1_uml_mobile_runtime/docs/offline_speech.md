# Voz offline

La primera integración usa `sherpa_onnx` 1.13.8 y audio PCM16 mono a 16 kHz.
El modelo configurado es `sherpa-onnx-streaming-zipformer-es-kroko-2025-08-06`,
un modelo Zipformer2 streaming para español orientado a CPU/Android arm64.

`ModelManager` guarda los cuatro archivos del modelo en:

`<applicationSupport>/models/asr/`

La instalación es lazy y descarga desde `https://huggingface.co/csukuangfj/`
`sherpa-onnx-streaming-zipformer-es-kroko-2025-08-06/resolve/main/` los
archivos `encoder.onnx`, `decoder.onnx`, `joiner.onnx` y `tokens.txt`; los archivos
parciales usan la extensión `.part` y no se consideran una instalación válida.
El APK no incluye el modelo. Si no está instalado, la app permite instalarlo o
cancelar y no bloquea el resto del runtime.

El motor usa `record` para capturar PCM16 a 16 kHz, alimenta el recognizer por
chunks y libera stream/recognizer al detener o destruir la pantalla. El audio
no se guarda ni se envía al backend.

El modelo debe validarse en el dispositivo objetivo antes de distribuir la app:
la URL y los nombres de archivos corresponden al repositorio del modelo y
pueden cambiar si el proveedor publica una revisión posterior.
