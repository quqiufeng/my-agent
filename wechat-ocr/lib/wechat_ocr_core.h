#ifndef WECHAT_OCR_CORE_H
#define WECHAT_OCR_CORE_H

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque handle for OCR engine */
typedef struct ocr_engine_t ocr_engine_t;

/*
 * Create OCR engine.
 * Returns opaque handle, or NULL on failure.
 */
ocr_engine_t* ocr_create(const char* det_model_path,
                          const char* rec_model_path,
                          const char* dict_path);

/*
 * Capture WeChat window and run OCR.
 * Returns JSON string array of text boxes:
 *   [{"x":int,"y":int,"w":int,"h":int,"text":"..."}, ...]
 * Caller must free with ocr_free_string().
 * Returns NULL on failure.
 */
char* ocr_capture(ocr_engine_t* engine);

/* Free a string returned by ocr_capture */
void ocr_free_string(char* str);

/* Destroy OCR engine */
void ocr_destroy(ocr_engine_t* engine);

/* Get last error message (valid until next API call) */
const char* ocr_last_error(ocr_engine_t* engine);

/*
 * Get the input box screen coordinates.
 * Returns JSON: {"x":int,"y":int,"w":int,"h":int}
 * Caller must free with ocr_free_string().
 * Returns NULL on failure.
 */
char* ocr_get_input_box(ocr_engine_t* engine);

/*
 * Find WeChat icon in the bottom taskbar and get its position.
 * Returns JSON: {"x":int,"y":int,"w":int,"h":int}
 * Caller must free with ocr_free_string().
 * Returns NULL if not found.
 */
char* ocr_find_taskbar_icon(ocr_engine_t* engine);

/*
 * Get the file send icon position (第3个图标, 📎).
 * Returns JSON: {"x":int,"y":int}
 * Caller must free with ocr_free_string().
 */
char* ocr_get_file_icon(ocr_engine_t* engine);

/*
 * Full window OCR, no timestamp filtering.
 * Returns all text boxes in the full window (including sidebar).
 * Caller must free with ocr_free_string().
 */
char* ocr_capture_all(ocr_engine_t* engine);

/*
 * Detect avatars in the second column (chat list).
 * Scans for colored square regions (avatars) in the left portion.
 * Returns JSON: {"avatars":[{"x":int,"y":int,"w":int,"h":int},...]}
 * Caller must free with ocr_free_string().
 */
char* ocr_detect_avatars(ocr_engine_t* engine);

#ifdef __cplusplus
}
#endif

#endif /* WECHAT_OCR_CORE_H */
