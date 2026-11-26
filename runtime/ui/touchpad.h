/*
 * The on-screen pad: a phone's thumbs as the Vita's controller.
 *
 * Laid out and hit-tested by window.c (where SDL's finger events arrive), drawn by the
 * overlay (overlay.cpp) from this struct, so layout and picture can never disagree.
 *
 * Layout, landscape, right-handed:
 *
 *   [ L ]  [select] [start]                                        [ R ]
 *
 *
 *
 *        ( O )                                          ( ^ )
 *      left pocket                                    ( < ) ( > )   face buttons
 *                                                        ( v )
 *
 * Both sticks are dynamic: a finger that lands in a pocket is the game's own
 * touch first -- a quick tap is a tap, wherever it lands -- and the moment it
 * holds (a sixth of a second) or drags (past ~12 points), its pocket's stick
 * spawns under it: base where the thumb landed, knob following. The movement
 * stick's pocket is the lower left (mirrored for the left-handed); the second
 * stick's is the lower right, and only where RECOMP_TOUCHPAD_RSTICK allows one.
 * The buttons and the shoulders are claimed the moment a finger touches them.
 * Tapping (not holding) the pad's controls is a control; everything else is
 * the game's screen.
 */
#ifndef RECOMP_TOUCHPAD_H
#define RECOMP_TOUCHPAD_H
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum { TP_LABEL_NONE, TP_LABEL_CROSS, TP_LABEL_CIRCLE, TP_LABEL_SQUARE, TP_LABEL_TRIANGLE,
       TP_LABEL_L, TP_LABEL_R, TP_LABEL_START, TP_LABEL_SELECT };

typedef struct {
	float x, y, r;      /* centre and radius (a shoulder is drawn as a rounded pill around it) */
	float hw, hh;       /* half-width/half-height when it is a pill (r == 0) */
	int pill;
	uint32_t bit;
	int label;
	int down;
} TpButton;

typedef struct {
	int on;             /* the pad is in use this frame */
	float w, h;         /* the window point size it was laid out for */
	float scale;        /* the player's size setting, 1.0 = 100% */

	float sl_x, sl_y, sl_r;   /* the left stick's base and reach */
	float sl_kx, sl_ky;       /* its knob */
	int   sl_active;

	float sr_x, sr_y, sr_r;   /* the right stick: where the thumb landed */
	float sr_kx, sr_ky;
	int   sr_active;

	int nb; TpButton b[8];
	int opacity;        /* 0..100, how solid the controls are */
	int mirror;         /* left-handed: sticks and buttons swap sides */
} TpVisual;

const TpVisual *touchpad_visuals(void);
void touchpad_layout_for(float w, float h);   /* overlay.cpp draws this; never null */
float touchpad_eye_x(void);                   /* the eye's corner x: valid with the pad off too */
int touchpad_on(void);
void touchpad_set_on(int on);
void touchpad_cancel_all(void); /* UI thread: release every screen button, stick and pending hold */
int touchpad_scale(void);                 /* percent, 60..160 */
void touchpad_set_scale(int percent);
int touchpad_mirror(void);
void touchpad_set_mirror(int on);

#ifdef __cplusplus
}
#endif

#endif
