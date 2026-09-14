#ifndef PORTHOLE_QUICKJS_H
#define PORTHOLE_QUICKJS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct PortholeJSRuntime PortholeJSRuntime;
typedef void (*PortholeJSInvoke)(void *context, uint64_t call_id,
                               const char *name, const char *arguments);
typedef bool (*PortholeJSInterrupt)(void *context);

/* All functions and callbacks run on one owner. The interrupt callback may read
   thread-safe cancellation state but must never call back into the engine. */
PortholeJSRuntime *porthole_js_create(size_t heap_bytes, size_t stack_bytes,
                                    size_t value_bytes, size_t native_calls,
                                    PortholeJSInvoke invoke,
                                    PortholeJSInterrupt interrupt, void *context);
void porthole_js_destroy(PortholeJSRuntime *runtime);
/* source is ordinary JavaScript, including top-level await. */
int porthole_js_begin(PortholeJSRuntime *runtime, const char *source);
/* Runs a bounded batch of promise jobs. 0 = pending, 1 = result, -1 = error. */
int porthole_js_pump(PortholeJSRuntime *runtime);
int porthole_js_complete(PortholeJSRuntime *runtime, uint64_t call_id,
                        const char *json, bool is_error);
/* Owned by runtime, valid until the next begin/destroy. */
const char *porthole_js_result(PortholeJSRuntime *runtime);
const char *porthole_js_error(PortholeJSRuntime *runtime);

#endif
