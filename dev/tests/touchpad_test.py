#!/usr/bin/env python3
"""Exercise the actual window.c pad code with deterministic SDL/clock/settings adapters.

Run on a host with a C compiler: python3 dev/tests/touchpad_test.py
No phone, game data, GPU or SDL installation is required. The production section is
compiled verbatim, so these tests cover its event routing and publication, not a Python replica.
"""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = (ROOT / 'runtime/ui/window.c').read_text(encoding='utf-8')
PAD = SOURCE.split('/* ---- the on-screen pad (touchpad.h):', 1)[1]
PAD = PAD[PAD.index('#include <math.h>'):].split('\nvoid window_input(', 1)[0]
WINDOW_INPUT = SOURCE[SOURCE.index('void window_input('):SOURCE.index('/* the Vita input an action presses')]
RELEASE = SOURCE[SOURCE.index('static void gamepad_touch_release(void) {'):SOURCE.index('/* A touchscreen (SDL')]
CLEAR = SOURCE[SOURCE.index('static void window_clear_input(void) {'):SOURCE.index('\n#if IOS_UI_CHROME\nstatic void ios_window_geometry_tick')]
CONTACTS = SOURCE[SOURCE.index('static int last_touch_key[2]'):SOURCE.index('static int clampi(')]
MOUSE = SOURCE[SOURCE.index('int window_mouse_delta(float *dx'):SOURCE.index('float window_mouse_sens(')]
ADAPTERS = r'''
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include "touchpad.h"
#define IOS_UI_CHROME 1
#define ST_FINGERS 10
typedef uint64_t SDL_FingerID;
typedef uint64_t SDL_TouchID;
enum { SDL_EVENT_FINGER_DOWN=1, SDL_EVENT_FINGER_UP, SDL_EVENT_FINGER_MOTION, SDL_EVENT_FINGER_CANCELED };
typedef struct { int type; struct { SDL_FingerID fingerID; float x, y; } tfinger; } SDL_Event;
enum { SELECT=1, START=8, LTRIG=0x100, RTRIG=0x200, TRIANGLE=0x1000, CIRCLE=0x2000, CROSS=0x4000, SQUARE=0x8000,
       L1=0x400, R1=0x800, L3=2, R3=4, PAD_L2=0x10000, PAD_R2=0x20000 };
static const char *keys[] = {"touchpad", "touchpad_scale", "touchpad_left", "touchpad_opacity", "touchpad_rstick"};
static int values[] = {1,100,0,42,1};
static int key_index(const char *key) { for (int i=0;i<5;i++) if (!strcmp(key,keys[i])) return i; return -1; }
static int settings_has(const char *key) { return key_index(key)>=0; }
static int settings_int(const char *key,int fallback) { int i=key_index(key); return i<0?fallback:values[i]; }
static void settings_set_int(const char *key,int value) { int i=key_index(key); assert(i>=0); values[i]=value; }
static void settings_save(void) {}
static float insets[4];
static void safe_insets(float *t,float *b,float *l,float *r) { *t=insets[0]; *b=insets[1]; *l=insets[2]; *r=insets[3]; }
static SDL_TouchID *SDL_GetTouchDevices(int *n) { *n=1; return NULL; }
static void SDL_free(void *p) { free(p); }
static uint64_t clock_ns;
static uint64_t SDL_GetTicksNS(void) { return clock_ns; }
static int menu, dialog;
static int overlay_is_open(void) { return menu; }
static int overlay_dialog_active(void) { return dialog; }
static int st_down[10], hold_st[10];
static SDL_FingerID st_id[10];
static int hold_release(int *p) { *p=0; return 1; }
static int hold_due(int *p) { (void)p; return 0; }
#define TP_FINGERS 6
#define KB_N 4
static int tp_down[TP_FINGERS], input_focused=1, buttons, touch_down;
static uint8_t sticks[4]={128,128,128,128};
static int16_t pad_raw[4];
static int cur_mode, cur_down, lb_held, rb_held, ltrig_on, rtrig_on, ptrig[2];
static int cur2_on, cur_used_l, cur_used_r, cur_cross, cur_trig[2], trig_touch[2];
static int twist_pad, twist_down, twist_drag, mouse_rear_down, gesture_drag, flick_down;
static int kbm_lmb, kbm_rmb, look_dx_q8, look_dy_q8, mouse_dx_q8, mouse_dy_q8;
static int kbm_on, pad_gyro, tilt_section, motion_pauses, native_cancels;
static int touch_x, touch_y, mouse_rear_x, mouse_rear_y, hold_mouse[2];
static int cur_x[2],cur_y[2],cur2_x[2],cur2_y[2],flick_x,flick_y,twist_x[2],twist_y[2];
static int tp_port[TP_FINGERS],tp_x[TP_FINGERS],tp_y[TP_FINGERS],hold_tp[TP_FINGERS];
static int st_port[ST_FINGERS],st_x[ST_FINGERS],st_y[ST_FINGERS];
static int rel_on=1,script_reads;
static uint64_t raw_taken_us;
static uint64_t now_us(void) { return clock_ns/1000; }
static int mouse_script(float *x,float *y) { script_reads++; *x=*y=0; return 0; }
static struct { int held; } kb_binds[KB_N];
static void motion_pause(void) { motion_pauses++; }
static void ios_ui_chrome_cancel_controls(void) { native_cancels++; }
static int touchpad_active(void) { for(int i=0;i<TP_FINGERS;i++) if(tp_down[i]) return 1; return 0; }
static int gesture_wanted(void) { return 0; }
static int twist_wanted(void) { return 0; }
static int pad_dbg(void);
static void ios_ui_chrome_place(float x);
static void ios_ui_pad_layout(void);
static void ios_ui_haptic(int kind) { assert(kind>=0 && kind<=2); }
'''
TESTS = r'''
static int native_layouts;
static void ios_ui_chrome_place(float x) { assert(x>=0 && x<tv.w); }
static void ios_ui_pad_layout(void) { assert(tv.on ? tv.nb==8 : tv.nb==0); native_layouts++; }
static SDL_Event finger(int type, uint64_t id, float x, float y) {
    SDL_Event e={0}; e.type=type; e.tfinger.fingerID=id; e.tfinger.x=x; e.tfinger.y=y; return e;
}
static void neutral(void) {
    uint32_t buttons=0; uint8_t sticks[4]={128,128,128,128};
    touchpad_read(&buttons,sticks); assert(!buttons);
    for(int i=0;i<4;i++) assert(sticks[i]==128);
}
static void geometry(void) {
    const int sizes[][2]={{568,320},{667,375},{736,414},{812,375},{896,414},{844,390},{852,393},{932,430}};
    const int scales[]={60,100,160};
    for(int d=0;d<8;d++) for(int sc=0;sc<3;sc++) for(int mirror=0;mirror<2;mirror++) for(int notch=0;notch<2;notch++) {
        touchpad_set_on(1); touchpad_set_scale(scales[sc]); touchpad_set_mirror(mirror);
        insets[1]=21; insets[2]=notch?59:0; insets[3]=notch?0:59;
        touchpad_layout_for(sizes[d][0],sizes[d][1]);
        assert(tv.nb==8 && tv.w==sizes[d][0] && tv.h==sizes[d][1]);
        for(int i=0;i<8;i++) {
            const TpButton *b=&tv.b[i];
            float hw=b->pill?b->hw:b->r, hh=b->pill?b->hh:b->r;
            assert(b->x-hw>=0 && b->x+hw<=tv.w && b->y-hh>=0 && b->y+hh<=tv.h);
        }
        const TpButton left=tv.b[mirror?5:4];
        assert(left.x-left.hw >= touchpad_eye_x()+54-0.01f);
        assert(tv.b[6].x-tv.b[6].hw > tv.w/2+32); /* visible Menu fits between Start and Select */
        assert(tv.b[7].x+tv.b[7].hw < tv.w/2-32);
    }
    puts("PASS: 96 phone/scale/mirror/notch layouts, bounds and reserved eye/Menu slots");
}
static void input(void) {
    touchpad_set_scale(100); touchpad_set_mirror(0); touchpad_set_on(1);
    touchpad_layout_for(932,430);
    touchpad_native_press(10); touchpad_native_press(11);
    assert((tp_bits&(TRIANGLE|CIRCLE))==(TRIANGLE|CIRCLE));
    touchpad_native_release(10); assert(tp_bits==CIRCLE);
    int layouts=native_layouts;
    values[3]=77; touchpad_layout_for(932,430);
    assert(tv.opacity==77 && tp_bits==CIRCLE && native_layouts==layouts);
    insets[2]=0; insets[3]=59; touchpad_layout_for(932,430);
    assert(native_layouts>layouts); neutral();
    touchpad_native_press(10); touchpad_set_on(0); neutral();
    touchpad_native_press(11); neutral();
    touchpad_layout_for(932,430); assert(!tv.on && !tv.nb);
    touchpad_set_on(1); touchpad_layout_for(932,430);
    touchpad_native_press(10); touchpad_set_mirror(1); touchpad_layout_for(932,430); neutral();
    touchpad_set_mirror(0); touchpad_layout_for(932,430);
    SDL_Event e=finger(SDL_EVENT_FINGER_DOWN,44,tv.b[2].x/tv.w,tv.b[2].y/tv.h);
    assert(touchpad_event(&e)); assert(tp_bits==CROSS);
    e.type=SDL_EVENT_FINGER_CANCELED; assert(touchpad_event(&e)); neutral();
    puts("PASS: multi-button release, live opacity, safe-area invalidation, hide/show, mirror and cancellation");
}
static void holds(void) {
    touchpad_cancel_all(); clock_ns=1000000000;
    SDL_Event e=finger(SDL_EVENT_FINGER_DOWN,55,0.2f,0.7f);
    assert(!tp_zone_hold(&e));
    clock_ns+=100000000; tp_zone_tick(); assert(!tv.sl_active);
    clock_ns+=100000000; tp_zone_tick(); assert(tv.sl_active);
    e.type=SDL_EVENT_FINGER_MOTION; e.tfinger.x=0.3f;
    assert(touchpad_event(&e));
    uint32_t buttons=0; uint8_t sticks[4]={128,128,128,128};
    touchpad_read(&buttons,sticks); assert(sticks[0]>128);
    touchpad_cancel_all(); neutral(); assert(!tv.sl_active);
    e=finger(SDL_EVENT_FINGER_DOWN,56,0.2f,0.7f); assert(!tp_zone_hold(&e));
    assert(!touchpad_event(&e)); /* an ordinary pocket tap still belongs to the game */
    clock_ns+=50000000; e.type=SDL_EVENT_FINGER_UP; assert(!tp_zone_hold(&e));
    clock_ns+=200000000; tp_zone_tick(); assert(!tv.sl_active);
    e=finger(SDL_EVENT_FINGER_DOWN,57,0.9f,0.7f); assert(!tp_zone_hold(&e));
    values[4]=0; clock_ns+=200000000; tp_zone_tick(); assert(!tv.sr_active);
    values[4]=1;
    e=finger(SDL_EVENT_FINGER_DOWN,58,0.99f,0.7f); assert(!tp_zone_hold(&e));
    clock_ns+=200000000; tp_zone_tick(); assert(tv.sr_active);
    const uint8_t x=tp_stick[2], y=tp_stick[3];
    e.type=SDL_EVENT_FINGER_MOTION; assert(touchpad_event(&e));
    assert(tp_stick[2]==x && tp_stick[3]==y); /* clamped base must not jump on the next motion */
    touchpad_cancel_all();
    e=finger(SDL_EVENT_FINGER_DOWN,59,0.2f,0.7f); assert(!tp_zone_hold(&e));
    menu=1; clock_ns+=200000000; tp_zone_tick(); assert(!tv.sl_active);
    touchpad_cancel_all(); menu=0; neutral();
    e=finger(SDL_EVENT_FINGER_DOWN,60,0.2f,0.7f); assert(!tp_zone_hold(&e));
    e.type=SDL_EVENT_FINGER_MOTION; e.tfinger.x=0.21f;
    assert(!tp_zone_hold(&e));
    clock_ns+=200000000; tp_zone_tick();
    assert(tv.sl_active && tv.sl_kx>tv.sl_x); /* use the last observed point after a small motion */
    touchpad_cancel_all(); neutral();
    puts("PASS: stationary hold, quick tap, disabled second stick, stable clamped base and menu interruption");
}
static int stop;
static void *read_input(void *unused) {
    (void)unused;
    while(!__atomic_load_n(&stop,__ATOMIC_ACQUIRE)) {
        const uint64_t value=__atomic_load_n(&tp_input,__ATOMIC_ACQUIRE);
        assert(value==UINT64_C(0x8080808000000000) || value==UINT64_C(0x1122334400001000));
    }
    return NULL;
}
static void publication(void) {
    touchpad_cancel_all(); pthread_t reader; assert(!pthread_create(&reader,NULL,read_input,NULL));
    for(int i=0;i<100000;i++) {
        tp_bits=TRIANGLE; tp_stick[0]=0x44; tp_stick[1]=0x33; tp_stick[2]=0x22; tp_stick[3]=0x11; tp_publish();
        tp_clear();
    }
    __atomic_store_n(&stop,1,__ATOMIC_RELEASE); pthread_join(reader,NULL); neutral();
    puts("PASS: 200,000 complete cross-thread input publications");
}
static void focus(void) {
    input_focused=0; buttons=LTRIG|RTRIG|PAD_L2|PAD_R2;
    uint32_t bits=~0u; uint8_t axes[4]={0,0,255,255};
    window_input(&bits,axes); assert(!bits);
    for(int i=0;i<4;i++) assert(axes[i]==128);
    window_input_pad2(&bits,axes); assert(!bits); /* no shoulder bits reintroduced by PS TV mapping */
    touch_down=1; int keys[8],xs[8],ys[8];
    assert(!window_touch_contacts(0,keys,xs,ys,8));
    mouse_dx_q8=512; mouse_dy_q8=-256; float dx=99,dy=99;
    assert(!window_mouse_delta(&dx,&dy) && dx==0 && dy==0 && !script_reads);
    for(int i=0;i<4;i++) { sticks[i]=255; pad_raw[i]=32767; kb_binds[i].held=1; }
    touch_down=flick_down=gesture_drag=twist_drag=twist_pad=twist_down=1;
    kbm_lmb=kbm_rmb=look_dx_q8=look_dy_q8=mouse_dx_q8=mouse_dy_q8=99;
    window_clear_input();
    assert(!buttons && !touch_down && !flick_down && !gesture_drag && !twist_drag && !twist_pad && !twist_down);
    assert(!kbm_lmb && !kbm_rmb && !look_dx_q8 && !look_dy_q8 && !mouse_dx_q8 && !mouse_dy_q8);
    for(int i=0;i<4;i++) assert(sticks[i]==128 && !pad_raw[i] && !kb_binds[i].held);
    assert(motion_pauses && native_cancels); input_focused=1; neutral();
    mouse_dx_q8=512; mouse_dy_q8=-256;
    assert(window_mouse_delta(&dx,&dy) && dx==2 && dy==-1);
    touch_down=1; touch_x=321; touch_y=654;
    assert(window_touch_contacts(0,keys,xs,ys,8)==1 && keys[0]==1 && xs[0]==321 && ys[0]==654);
    window_clear_input();
    puts("PASS: background buttons/axes/touch/raw-mouse suppression, PS TV mapping and full gesture/key release");
}
int main(void) { geometry(); input(); holds(); publication(); focus(); return 0; }
'''
with tempfile.TemporaryDirectory(prefix='nativ-touchpad-') as folder:
    source = Path(folder) / 'test.c'
    binary = Path(folder) / 'test'
    source.write_text(ADAPTERS + RELEASE + CONTACTS + MOUSE + PAD + WINDOW_INPUT + CLEAR + TESTS, encoding='utf-8')
    command = [os.environ.get('CC', 'cc'), '-std=c11', '-O1', '-g', '-Wall', '-Wextra', '-Werror',
               '-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-I', str(ROOT / 'runtime/ui'),
               str(source), '-lm', '-pthread', '-o', str(binary)]
    subprocess.run(command, check=True)
    test_env = os.environ.copy()
    for key in ('RECOMP_TOUCHPAD', 'RECOMP_TOUCHPAD_RSTICK', 'RECOMP_STICK_HOLD', 'RECOMP_STICK_DRAG'):
        test_env.pop(key, None)
    subprocess.run([str(binary)], check=True, env=test_env)
