#include "include/PortholeQuickJS.h"
#include "vendor/quickjs.h"
#include <stdlib.h>
#include <string.h>

typedef struct NativeCall {
    uint64_t id;
    JSValue resolve;
    JSValue reject;
    struct NativeCall *next;
} NativeCall;

struct PortholeJSRuntime {
    JSRuntime *runtime;
    JSContext *context;
    JSValue promise;
    JSValue decode;
    JSValue encode;
    NativeCall *calls;
    uint64_t next_call_id;
    size_t call_count;
    size_t max_calls;
    size_t max_value_bytes;
    PortholeJSInvoke invoke;
    PortholeJSInterrupt interrupt;
    void *opaque;
    char *result;
    char *error;
};

static void set_error(PortholeJSRuntime *runtime, const char *message) {
    free(runtime->error);
    runtime->error = strdup(message ? message : "JavaScript execution failed");
}

static void capture_error(PortholeJSRuntime *runtime, JSValue exception) {
    const char *message = JS_ToCString(runtime->context, exception);
    set_error(runtime, message);
    if (message) JS_FreeCString(runtime->context, message);
    JS_FreeValue(runtime->context, exception);
}

static int interrupted(JSRuntime *engine, void *opaque) {
    (void)engine;
    PortholeJSRuntime *runtime = opaque;
    return runtime->interrupt(runtime->opaque);
}

static void clear_calls(PortholeJSRuntime *runtime) {
    while (runtime->calls) {
        NativeCall *call = runtime->calls;
        runtime->calls = call->next;
        JS_FreeValue(runtime->context, call->resolve);
        JS_FreeValue(runtime->context, call->reject);
        free(call);
    }
}

static JSValue encode_value(PortholeJSRuntime *runtime, JSValueConst value) {
    return JS_Call(runtime->context, runtime->encode, JS_UNDEFINED, 1, &value);
}

static JSValue invoke_native(JSContext *context, JSValueConst this_value,
                             int argc, JSValueConst *argv) {
    (void)this_value;
    PortholeJSRuntime *runtime = JS_GetContextOpaque(context);
    if (argc != 2 || !JS_IsString(argv[0]))
        return JS_ThrowTypeError(context, "Use porthole.call(name, arguments)");
    if (runtime->call_count >= runtime->max_calls)
        return JS_ThrowRangeError(context, "Native call limit exceeded");
    size_t name_length = 0;
    const char *name = JS_ToCStringLen(context, &name_length, argv[0]);
    if (!name) return JS_EXCEPTION;
    if (name_length == 0 || name_length > 512 || strlen(name) != name_length) {
        JS_FreeCString(context, name);
        return JS_ThrowTypeError(context, "The capability name is invalid");
    }
    JSValue encoded = encode_value(runtime, argv[1]);
    if (JS_IsException(encoded) || JS_IsUndefined(encoded)) {
        JS_FreeCString(context, name);
        if (JS_IsException(encoded)) return encoded;
        return JS_ThrowTypeError(context, "Arguments must be JSON values");
    }
    size_t length = 0;
    const char *arguments = JS_ToCStringLen(context, &length, encoded);
    JS_FreeValue(context, encoded);
    if (!arguments || length > runtime->max_value_bytes) {
        if (arguments) JS_FreeCString(context, arguments);
        JS_FreeCString(context, name);
        return JS_ThrowRangeError(context, "Arguments exceed the value limit");
    }
    NativeCall *call = calloc(1, sizeof(*call));
    if (!call) {
        JS_FreeCString(context, name);
        JS_FreeCString(context, arguments);
        return JS_ThrowOutOfMemory(context);
    }
    JSValue resolvers[2];
    JSValue promise = JS_NewPromiseCapability(context, resolvers);
    if (JS_IsException(promise)) {
        free(call);
    } else {
        call->id = ++runtime->next_call_id;
        call->resolve = resolvers[0];
        call->reject = resolvers[1];
        call->next = runtime->calls;
        runtime->calls = call;
        runtime->call_count++;
        runtime->invoke(runtime->opaque, call->id, name, arguments);
    }
    JS_FreeCString(context, name);
    JS_FreeCString(context, arguments);
    return promise;
}

PortholeJSRuntime *porthole_js_create(size_t heap_bytes, size_t stack_bytes,
                                    size_t value_bytes, size_t native_calls,
                                    PortholeJSInvoke invoke,
                                    PortholeJSInterrupt interrupt, void *opaque) {
    PortholeJSRuntime *runtime = calloc(1, sizeof(*runtime));
    if (!runtime) return NULL;
    runtime->runtime = JS_NewRuntime();
    if (!runtime->runtime) { free(runtime); return NULL; }
    JS_SetMemoryLimit(runtime->runtime, heap_bytes);
    JS_SetMaxStackSize(runtime->runtime, stack_bytes);
    JS_SetCanBlock(runtime->runtime, false);
    runtime->context = JS_NewContext(runtime->runtime);
    if (!runtime->context) {
        JS_FreeRuntime(runtime->runtime);
        free(runtime);
        return NULL;
    }
    runtime->promise = JS_UNDEFINED;
    runtime->decode = JS_UNDEFINED;
    runtime->encode = JS_UNDEFINED;
    runtime->invoke = invoke;
    runtime->interrupt = interrupt;
    runtime->opaque = opaque;
    runtime->max_value_bytes = value_bytes;
    runtime->max_calls = native_calls;
    JS_SetContextOpaque(runtime->context, runtime);
    JS_SetInterruptHandler(runtime->runtime, interrupted, runtime);
    /* Retain these closures privately. User code cannot replace the bridge codec.
       JSON.parse's source context preserves Int64 and UInt64 values before Number rounding.
       JSON.rawJSON writes BigInt values without a tagged-object collision. */
    static const char codec[] =
        "(() => { const parse = JSON.parse, stringify = JSON.stringify, raw = JSON.rawJSON;"
        " const safe = Number.isSafeInteger, integral = Number.isInteger, finite = Number.isFinite, big = BigInt;"
        " const text = Function.prototype.call.bind(BigInt.prototype.toString);"
        " const integer = Function.prototype.call.bind(RegExp.prototype.test, /^-?[0-9]+$/);"
        " return [s => parse(s, (k,v,c) => typeof v === 'number' && integral(v) && !safe(v) ? (integer(c.source) ? big(c.source) : big(v)) : v),"
        " v => stringify(v, (k,x) => {"
        " if (typeof x === 'bigint') { if (x < -9223372036854775808n || x > 18446744073709551615n) throw new RangeError('BigInt exceeds the Int64/UInt64 range'); return raw(text(x)); }"
        " if (typeof x === 'number' && integral(x) && !safe(x)) throw new RangeError('Unsafe integer Number; use a BigInt literal');"
        " if (typeof x === 'undefined' || typeof x === 'function' || typeof x === 'symbol' || (typeof x === 'number' && !finite(x))) throw new TypeError('Values must be JSON values');"
        " return x; })]; })()";
    JSValue codecs = JS_Eval(runtime->context, codec, sizeof(codec) - 1,
                             "porthole-codec.js", JS_EVAL_TYPE_GLOBAL);
    if (JS_IsException(codecs)) { porthole_js_destroy(runtime); return NULL; }
    runtime->decode = JS_GetPropertyUint32(runtime->context, codecs, 0);
    runtime->encode = JS_GetPropertyUint32(runtime->context, codecs, 1);
    JS_FreeValue(runtime->context, codecs);
    JSValue global = JS_GetGlobalObject(runtime->context);
    JSValue porthole = JS_NewObject(runtime->context);
    if (JS_IsException(global) || JS_IsException(porthole) ||
        JS_SetPropertyStr(runtime->context, porthole, "call",
                         JS_NewCFunction(runtime->context, invoke_native, "call", 2)) < 0) {
        JS_FreeValue(runtime->context, global);
        JS_FreeValue(runtime->context, porthole);
        porthole_js_destroy(runtime);
        return NULL;
    }
    int installed = JS_SetPropertyStr(runtime->context, global, "porthole", porthole);
    JS_FreeValue(runtime->context, global);
    if (installed < 0) { porthole_js_destroy(runtime); return NULL; }
    return runtime;
}

void porthole_js_destroy(PortholeJSRuntime *runtime) {
    if (!runtime) return;
    clear_calls(runtime);
    JS_FreeValue(runtime->context, runtime->promise);
    JS_FreeValue(runtime->context, runtime->decode);
    JS_FreeValue(runtime->context, runtime->encode);
    JS_FreeContext(runtime->context);
    JS_FreeRuntime(runtime->runtime);
    free(runtime->result);
    free(runtime->error);
    free(runtime);
}

int porthole_js_begin(PortholeJSRuntime *runtime, const char *source) {
    JS_UpdateStackTop(runtime->runtime);
    clear_calls(runtime);
    JS_FreeValue(runtime->context, runtime->promise);
    runtime->promise = JS_UNDEFINED;
    runtime->call_count = 0;
    free(runtime->result); runtime->result = NULL;
    free(runtime->error); runtime->error = NULL;
    runtime->promise = JS_Eval(runtime->context, source, strlen(source),
                               "porthole-console.js", JS_EVAL_TYPE_GLOBAL | JS_EVAL_FLAG_ASYNC);
    if (JS_IsException(runtime->promise)) {
        runtime->promise = JS_UNDEFINED;
        capture_error(runtime, JS_GetException(runtime->context));
        return -1;
    }
    return 0;
}

int porthole_js_complete(PortholeJSRuntime *runtime, uint64_t call_id,
                        const char *json, bool is_error) {
    NativeCall **cursor = &runtime->calls;
    while (*cursor && (*cursor)->id != call_id) cursor = &(*cursor)->next;
    if (!*cursor) return 0;
    NativeCall *call = *cursor;
    *cursor = call->next;
    JSValue text = JS_NewString(runtime->context, json);
    JSValue value = JS_Call(runtime->context, runtime->decode, JS_UNDEFINED, 1, &text);
    JS_FreeValue(runtime->context, text);
    if (JS_IsException(value)) {
        value = JS_GetException(runtime->context);
        is_error = true;
    }
    JSValue result = JS_Call(runtime->context, is_error ? call->reject : call->resolve,
                             JS_UNDEFINED, 1, &value);
    JS_FreeValue(runtime->context, value);
    JS_FreeValue(runtime->context, call->resolve);
    JS_FreeValue(runtime->context, call->reject);
    free(call);
    if (JS_IsException(result)) {
        capture_error(runtime, JS_GetException(runtime->context));
        return -1;
    }
    JS_FreeValue(runtime->context, result);
    return 0;
}

int porthole_js_pump(PortholeJSRuntime *runtime) {
    JS_UpdateStackTop(runtime->runtime);
    for (int i = 0; i < 64 && JS_IsJobPending(runtime->runtime); i++) {
        JSContext *context = NULL;
        if (JS_ExecutePendingJob(runtime->runtime, &context) < 0) {
            capture_error(runtime, JS_GetException(context));
            return -1;
        }
    }
    JSPromiseStateEnum state = JS_PromiseState(runtime->context, runtime->promise);
    if (state == JS_PROMISE_PENDING) return 0;
    JSValue result = JS_PromiseResult(runtime->context, runtime->promise);
    if (state == JS_PROMISE_REJECTED) {
        capture_error(runtime, result);
        return -1;
    }
    /* ASYNC global evaluation resolves to { value: <last expression> }. */
    JSValue value = JS_GetPropertyStr(runtime->context, result, "value");
    JS_FreeValue(runtime->context, result);
    JSValue encoded = JS_IsUndefined(value) ? JS_NewString(runtime->context, "null") :
        encode_value(runtime, value);
    JS_FreeValue(runtime->context, value);
    if (JS_IsException(encoded)) {
        capture_error(runtime, JS_GetException(runtime->context));
        return -1;
    }
    if (JS_IsUndefined(encoded)) {
        set_error(runtime, "The result is not a JSON value");
        return -1;
    }
    size_t length = 0;
    const char *json = JS_ToCStringLen(runtime->context, &length, encoded);
    JS_FreeValue(runtime->context, encoded);
    if (!json || length > runtime->max_value_bytes) {
        if (json) JS_FreeCString(runtime->context, json);
        set_error(runtime, "The result exceeds the value limit");
        return -1;
    }
    runtime->result = strdup(json);
    JS_FreeCString(runtime->context, json);
    if (!runtime->result) { set_error(runtime, "The result allocation failed"); return -1; }
    return 1;
}

const char *porthole_js_result(PortholeJSRuntime *runtime) { return runtime->result; }
const char *porthole_js_error(PortholeJSRuntime *runtime) { return runtime->error; }
