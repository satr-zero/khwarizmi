# خطة نظام Logging موحد — خوارزمي

## المشكلة الجذرية (Root Causes)

بعد الفحص الدقيق، الأسباب الحقيقية لتوقف الوكيل فجأة:

| # | السبب | الموقع | التفاصيل |
|---|--------|---------|-----------|
| 1 | **Stream Idle Timeout (90ث)** | `AgentStreamWatchdog` | يلغي الاشتراك إذا سكت البث 90 ثانية — لا يطبع شيئاً في التيرمنال قبل الإلغاء |
| 2 | **Empty Model Response** | `TaskExecutionEngine._executeSubTask:643` | النماذج ذات التفكير (thinking) قد تُصدر `thought` فقط بدون `text` → يُرمى استثناء ويوقف الحلقة |
| 3 | **Silent End After Tools** | `ChatController._runAgentLoop:1086` | بعد تنفيذ أدوات، إذا انتهى النموذج بصمت → يعيد المحاولة مرة واحدة فقط ثم يسقط |
| 4 | **Promise Recovery Exhausted** | `ExecutionPromiseGuard` | حد أقصى `maxAutoRecoveriesPerUserTurn = 1` — إذا واصل النموذج الوعود يتوقف نهائياً |
| 5 | **Swallowed Exceptions** | في كل مكان `catch (_) {}` | أخطاء حقيقية تُبتلع صامتاً — لا تظهر في التيرمنال |
| 6 | **No Token Exhaustion Handling** | غير موجود | لا يوجد كود يكشف `token limit` ويستأنف تلقائياً (checkpoint/resume) |
| 7 | **AgentDoneEvent Missing** | Provider streams | إذا لم يُصدر المزوّد `AgentDoneEvent` → يظل البث معلقاً حتى `watchdog` يقتله |
| 8 | **Retry Exhaustion Silent** | `RetryUtils.executeStreamWithRetry:205` | بعد 3 محاولات يرمي الخطأ الأخير — لكن قد لا يُسجل بوضوح |

---

## الحل: نظام Logging موحد (Unified Logging System)

### مبادئ التصميم
1. **كل شيء في التيرمنال** — لا `debugPrint` متناثر، قناة واحدة موحدة
2. **مستويات واضحة** — `TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`, `CRITICAL`
3. **سياق غني** — `correlationId`، `taskId`، `turnId`، `provider`، `model`
4. **JSON Lines** — قابل للتبعي (`tail -f`) والتحليل الآلي
5. **إيقاف/تشغيل ديناميكي** — عبر إعدادات الواجهة

### البنية المقترحة

```
lib/core/logging/
├── logger.dart              # واجهة موحدة (Logger, LogLevel, LogEntry)
├── terminal_sink.dart       # مصرف التيرمنال (ألوان، تنسيق)
├── file_sink.dart           # مصرف ملفات (تدوير يومي، JSONL)
├── logging_mixin.dart       # Mixin لإضافة `log` لأي كلاس
├── provider_logger.dart     # غلاف للمزودين (يلف sendMessage)
├── tool_logger.dart         # غلاف لـ ToolRegistry.executeTool
├── stream_logger.dart       # غلاف للبث (watchdog، retry، chunks)
├── task_logger.dart         # غلاف لـ TaskExecutionEngine
└── interceptor_logger.dart  # غلاف لـ UnifiedInterceptor
```

### نقاط الربط (Instrumentation Points)

| المكون | ما يُسجل | المستوى |
|----------|----------|---------|
| **Provider.sendMessage** | طلب/استجابة، نموذج، أدوات، thinking config | INFO |
| **Stream chunks** | كل `AgentTextChunk`، `AgentThinkingChunk`، `AgentToolCall`، `AgentRetryEvent`، `AgentErrorEvent`، `AgentDoneEvent` | TRACE/DEBUG |
| **Watchdog** | بدء، كل `onEvent`، timeout fired | DEBUG/WARN |
| **RetryUtils** | محاولة، خطأ، تأخير، استنفاد | WARN/ERROR |
| **ToolRegistry.executeTool** | أداة، Args (مُقننة)، نتيجة، مهلة، إلغاء | INFO |
| **TaskExecutionEngine** | مهمة، خطة، مهمة فرعية، محاولة، نجاح/فشل، checkpoint | INFO |
| **UnifiedInterceptor** | اعتراض، عداد وعود، إجراء، حقن رسائل | WARN |
| **ChatController._runAgentLoop** | بداية/نهاية حلقة، رسائل، أدوات، استرداد | INFO |
| **Promise Guard** | وعد مكتشف، عداد، محاولة استرداد | WARN |

### تنسيق السطر (JSONL)

```json
{
  "ts": "2026-09-26T17:57:12.345Z",
  "lvl": "INFO",
  "ctx": "Provider.sendMessage",
  "corr": "a1b2c3d4",
  "task": "task-5678",
  "turn": "turn-9012",
  "prov": "gemini",
  "model": "gemini-3.8-flash",
  "msg": "Stream started",
  "meta": {"tools": 12, "thinking": "fixed:8000"}
}
```

---

## خطة التنفيذ (مرحلية)

### Phase 1: البنية الأساسية (أولوية قصوى)
- [ ] `Logger` singleton مع `LogLevel` و `LogEntry`
- [ ] `TerminalSink` مع ألوان ANSI و تنسيق جميل
- [ ] `LoggingMixin` للاستخدام السهل: `log.info('msg', meta: {...})`
- [ ] إعداد عام `LoggingConfig` (مستوى، ألوان، ملف، إلخ)

### Phase 2: تغليف النقاط الحرجة
- [ ] `ProviderLogger` يلف `AiProvider.sendMessage` — يسجل طلب/استجابة كاملين
- [ ] `StreamLogger` يلف `RetryUtils.executeStreamWithRetry` — يسجل كل chunk و retry
- [ ] `WatchdogLogger` يلف `AgentStreamWatchdog` — يسجل بدء/أحداث/timeout
- [ ] `ToolLogger` يلف `ToolRegistry.executeTool` — يسجل استدعاء/نتيجة/مهلة

### Phase 3: المهام والاعتراض
- [ ] `TaskLogger` في `TaskExecutionEngine` — خطة، مهام فرعية، محاولات، checkpoint
- [ ] `InterceptorLogger` في `UnifiedInterceptor` — اعتراضات، وعود، حقن
- [ ] `ChatLoopLogger` في `_runAgentLoop` — حلقات، رسائل، أدوات، استرداد

### Phase 4: تكامل واجهة المستخدم
- [ ] إعدادات Logging في `SettingsDialog` (مستوى، ألوان، ملف، تصفية)
- [ ] أمر `LoggingConfig` في التيرمنال لتغيير المستوى حياً
- [ ] تصدير السجلات (Copy/Export) من الواجهة

### Phase 5: تشخيص تلقائي (Self-Diagnostics)
- [ ] كشف أنماط الفشل الشائعة (timeout متكرر، empty response، promise loop)
- [ ] اقتراحات إصلاح تلقائية في السجل: `"SUGGESTION: Increase idleTimeout or check network"`
- [ ] ملخص جلسة عند الإغلاق: إجمالي الطلبات، أخطاء، إعادة محاولات، وقت

---

## مثال مخرجات التيرمنال (المطلوب)

```
[INFO ] 17:57:12.345 [corr:a1b2c3d4] Provider.sendMessage → gemini:gemini-3.8-flash tools=12 thinking=fixed:8000
[TRACE] 17:57:12.347 [corr:a1b2c3d4] Stream chunk: AgentTextChunk(len=24)
[TRACE] 17:57:12.349 [corr:a1b2c3d4] Stream chunk: AgentThinkingChunk(len=156)
[TRACE] 17:57:12.351 [corr:a1b2c3d4] Stream chunk: AgentToolCall(name=web_search, callId=call_123)
[DEBUG] 17:57:12.352 [corr:a1b2c3d4] Watchdog.onEvent() reset timer (90s)
[INFO ] 17:57:15.112 [corr:a1b2c3d4] ToolRegistry.executeTool → web_search args={query:"..."} timeout=30s
[INFO ] 17:57:18.004 [corr:a1b2c3d4] ToolRegistry.executeTool ← web_search OK (2.9s) result_len=1240
[TRACE] 17:57:18.005 [corr:a1b2c3d4] Stream chunk: AgentTextChunk(len=87)
[INFO ] 17:57:18.007 [corr:a1b2c3d4] Stream chunk: AgentDoneEvent
[INFO ] 17:57:18.008 [corr:a1b2c3d4] _runAgentLoop turn complete → toolCalls=1, content_len=111
[WARN ] 17:57:18.009 [corr:a1b2c3d4] UnifiedInterceptor: consecutive=2 action=interceptAndRecover recoveryAttempt=0
[INFO ] 17:57:18.010 [corr:a1b2c3d4] Recovery injection → re-running agent loop (attempt 1)
[INFO ] 17:57:22.145 [corr:a1b2c3d4] Provider.sendMessage → gemini:gemini-3.8-flash (recovery)
[TRACE] 17:57:22.147 [corr:a1b2c3d4] Stream chunk: AgentToolCall(name=deliver_file, callId=call_456)
[INFO ] 17:57:22.148 [corr:a1b2c3d4] ToolRegistry.executeTool → deliver_file args={path:"...", content:"..."} timeout=10s
[INFO ] 17:57:22.155 [corr:a1b2c3d4] ToolRegistry.executeTool ← deliver_file OK (0.007s)
[INFO ] 17:57:22.156 [corr:a1b2c3d4] _runAgentLoop turn complete → toolCalls=1, content_len=0
[INFO ] 17:57:22.157 [corr:a1b2c3d4] Agent loop ended normally
```

---

## معالجة "انتهاء التوكنز" (Token Exhaustion + Checkpoint/Resume)

إضافة في `ProviderLogger` و `TaskLogger`:

1. **كشف الخطأ**: فحص `errorString` يحتوي على `token limit` أو `max_tokens` أو `400` مع رسالة توكنز
2. **Checkpoint**: حفظ `history` الحالية + `toolCalls` المنفذة + `partialResponse`
3. **Resume**: طلب جديد مع `history` مختصرة (تلخيص) + استكمال من آخر أداة
4. **تسجيل**: `[WARN] Token exhaustion detected → checkpoint saved → resuming with summarized history`

---

## الموافقة المطلوبة

هل نبدأ بـ **Phase 1** فوراً؟ أم تريد تعديل الخطة أولاً؟