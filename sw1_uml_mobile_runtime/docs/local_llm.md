# LLM local para comandos

La interpretación IA usa `llama_flutter_android: ^0.2.6`, un binding local de
llama.cpp para Android. No se envía texto ni audio a ningún servicio externo.

## Modelo

- Modelo: Qwen3-0.6B GGUF.
- Cuantización: `Q4_K_M`.
- Archivo: `Qwen3-0.6B-Q4_K_M.gguf`.
- Tamaño aproximado: 484 MB.
- URL: `https://huggingface.co/QuantFactory/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B.Q4_K_M.gguf?download=true`.
- Almacenamiento: `ApplicationSupport/models/llm/qwen3-0.6b/`.

El modelo se descarga una vez, usa archivo `.part`, Range/reintento básico y se
valida por tamaño antes de quedar instalado. La instalación es independiente
del modelo Sherpa ASR.

## Flujo seguro

`texto (o Sherpa ASR) -> LocalLlmCommandInterpreter -> JSON -> LlmIntentParser -> CommandIntent -> CommandExecutor`.

El prompt contiene únicamente el runtime-schema resumido. El modelo no tiene
acceso a HTTP, base de datos, repositorio ni herramientas. El parser rechaza
JSON inválido, entidades/campos inventados, IDs faltantes, tipos inválidos y
ambigüedades. DELETE continúa requiriendo confirmación en `CommandExecutor`.

Si el modelo no está instalado, falla la carga o su respuesta no alcanza la
confianza mínima, se usa `LocalCommandInterpreter` sin mostrar detalles
técnicos al usuario.

La configuración inicial es contexto 2048, 4 hilos, temperatura 0.1, top-p
0.5 y máximo 256 tokens. Se intenta Vulkan con las capas recomendadas por el
plugin; llama.cpp puede continuar en CPU si no hay capas GPU disponibles.

## Limitaciones

Qwen3-0.6B es pequeño y puede requerir frases claras en español. No hay
memoria conversacional, RAG, tool calling ni ejecución masiva. La descarga
inicial requiere red; la inferencia posterior es local y funciona sin backend.
