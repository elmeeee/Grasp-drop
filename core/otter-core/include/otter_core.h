#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

/**
 * Default port for both multicast UDP and the HTTP(S) server.
 */
#define DEFAULT_PORT 53317

/**
 * Default port for the browser portal.
 */
#define WEB_HUB_PORT 7456

/**
 * Opaque node handle exposed across the FFI boundary.
 */
typedef struct OtterNodeHandle OtterNodeHandle;

#ifdef __cplusplus
extern "C" {
#endif // __cplusplus

/**
 * Starts a Otter node and returns an opaque handle, or null on failure.
 *
 * # Safety
 * The returned handle must eventually be released with `otter_node_stop`.
 */
struct OtterNodeHandle *otter_node_start(const char *alias,
                                         const char *state_dir,
                                         const char *files_dir);

/**
 * Stops a node and frees its handle.
 *
 * # Safety
 * `handle` must have been returned by `otter_node_start` and not used again.
 */
void otter_node_stop(struct OtterNodeHandle *handle);

/**
 * Returns the device fingerprint as a newly allocated C string.
 *
 * # Safety
 * `handle` must be a valid pointer from `otter_node_start`. The caller owns the
 * returned string and must release it with `otter_string_free`.
 */
char *otter_node_fingerprint(const struct OtterNodeHandle *handle);

/**
 * Returns the discovered peers as a JSON array string.
 *
 * # Safety
 * Same contract as `otter_node_fingerprint`.
 */
char *otter_node_peers(const struct OtterNodeHandle *handle);

/**
 * Frees a string returned by the FFI functions above.
 *
 * # Safety
 * `value` must come from one of the functions returning `*mut c_char`.
 */
void otter_string_free(char *value);

#ifdef __cplusplus
}  // extern "C"
#endif  // __cplusplus
