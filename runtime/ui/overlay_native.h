#ifndef NATIV_OVERLAY_NATIVE_H
#define NATIV_OVERLAY_NATIVE_H
typedef union SDL_Event SDL_Event;
#ifdef __cplusplus
extern "C" {
#endif
enum { NATIVE_CARD_NONE, NATIVE_CARD_QUIT, NATIVE_CARD_LAYOUT, NATIVE_CARD_PREP };
typedef struct {
    int kind, seq, done, total, prep_state;
    double eta;
} NativeOverlayState;
void overlay_native_state(NativeOverlayState *state);
void overlay_native_answer(int kind, int seq, int choice, int remember);
int ios_ui_chrome_handle_event(const SDL_Event *event);
void ios_ui_chrome_marks(const void *marks, int count, const float rear[4]);
#ifdef __cplusplus
}
#endif
#endif
