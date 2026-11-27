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
HOOKS = (ROOT / 'packs/PCSA00029/hooks.c').read_text(encoding='utf-8')
HOOKS = HOOKS[HOOKS.index('static float uc_mx, uc_my;'):]
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
static const char *keys[] = {"touchpad", "touchpad_scale", "touchpad_left", "touchpad_opacity", "touchpad_rstick", "touch_look"};
static int values[] = {1,100,0,42,1,0};
static float touch_sens=1;
static int key_index(const char *key) { for (int i=0;i<6;i++) if (!strcmp(key,keys[i])) return i; return -1; }
static double settings_float(const char *key,double fallback) { return !strcmp(key,"touch_sens") ? touch_sens : fallback; }
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
static int game_gesture,game_twist;
static int gesture_wanted(void) { return game_gesture; }
static int twist_wanted(void) { return game_twist; }
typedef struct { uint32_t r[16]; } Cpu;
static uint32_t guest[1024];
#define RD32(a) (guest[(a)/4])
#define WR32(a,b) (guest[(a)/4]=(b))
static int raw_mouse=1, invert_mouse;
static float mouse_sens=1;
static int window_raw_look(void) { return raw_mouse; }
static int window_mouse_invert(void) { return invert_mouse; }
static float window_mouse_sens(void) { return mouse_sens; }
static void uc_camera_diag(void) {}
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
static void close_to(float actual,float expected) { assert(fabsf(actual-expected)<0.0003f); }
static SDL_Event start_look(uint64_t id) {
    SDL_Event e=finger(SDL_EVENT_FINGER_DOWN,id,0.6f,0.35f);
    assert(!touchpad_event(&e) && !tp_zone_hold(&e));
    return e;
}
static float drag_total(int samples,int read_every) {
    touchpad_cancel_all(); SDL_Event e=start_look(100); float total=0,dx,dy;
    for(int i=1;i<=samples;i++) {
        clock_ns+=1000000000ull/samples;
        e.type=SDL_EVENT_FINGER_MOTION; e.tfinger.x=0.6f+0.2f*i/samples;
        if(!touchpad_event(&e)) tp_zone_hold(&e);
        if(i%read_every==0) { window_touch_look_delta(&dx,&dy); total+=dx; }
    }
    e.type=SDL_EVENT_FINGER_UP; assert(touchpad_event(&e));
    window_touch_look_delta(&dx,&dy); return total+dx;
}
static void direct_look(void) {
    setenv("RECOMP_TOUCH_LOOK","1",1); values[5]=1; clock_ns+=1000000000;
    touchpad_cancel_all(); touchpad_layout_for(932,430);
    SDL_Event e=start_look(80); float dx,dy;
    st_down[0]=1; st_id[0]=80; hold_st[0]=1;
    clock_ns+=1000000000; tp_zone_tick(); assert(!tl_active); /* holding is still a game touch */
    e.type=SDL_EVENT_FINGER_MOTION; e.tfinger.x+=2.0f/tv.w;
    assert(!tp_zone_hold(&e));
    e.tfinger.x+=2.0f/tv.w; assert(tp_zone_hold(&e) && tl_active && !tv.sr_active);
    assert(!st_down[0]); /* camera ownership releases the preceding game touch */
    assert(window_touch_look_delta(&dx,&dy)); close_to(dx,4.0f/tv.w*3.14159265f); close_to(dy,0);
    neutral(); assert(!window_touch_look_delta(&dx,&dy));
    clock_ns+=1000000000; tp_zone_tick(); assert(tl_active); /* stationary ownership remains exclusive */
    SDL_Event other=start_look(81); other.type=SDL_EVENT_FINGER_MOTION; other.tfinger.x=0.75f;
    assert(!tp_zone_hold(&other)); assert(!window_touch_look_delta(&dx,&dy));
    SDL_Event move=finger(SDL_EVENT_FINGER_DOWN,89,0.2f,0.7f); assert(!tp_zone_hold(&move));
    move.type=SDL_EVENT_FINGER_MOTION; move.tfinger.x=0.25f; assert(tp_zone_hold(&move));
    assert(tv.sl_active && tl_active && tp_stick[0]>128 && tp_stick[2]==128 && tp_stick[3]==128);
    touchpad_native_press(10); assert(tp_bits&TRIANGLE); touchpad_native_release(10);
    move.type=SDL_EVENT_FINGER_UP; assert(touchpad_event(&move) && tl_active);
    e.tfinger.x-=1.0f/tv.w; assert(touchpad_event(&e));
    assert(window_touch_look_delta(&dx,&dy)); close_to(dx,-1.0f/tv.w*3.14159265f); /* no active-drag dead zone */
    e.type=SDL_EVENT_FINGER_UP; e.tfinger.x+=10.0f/tv.w; assert(touchpad_event(&e) && !tl_active);
    assert(window_touch_look_delta(&dx,&dy)); close_to(dx,10.0f/tv.w*3.14159265f); /* release retains last segment */
    assert(!window_touch_look_delta(&dx,&dy));
    close_to(drag_total(120,2),0.2f*3.14159265f); /* 60 camera samples/s */
    close_to(drag_total(120,4),0.2f*3.14159265f); /* 30 camera samples/s */
    close_to(drag_total(4,4),0.2f*3.14159265f);   /* sparse/coalesced events, consumed after lift */
    touch_sens=2; clock_ns+=1000000000; close_to(drag_total(60,2),0.4f*3.14159265f);
    touch_sens=1; clock_ns+=1000000000;
    e=start_look(82); e.type=SDL_EVENT_FINGER_MOTION; e.tfinger.x=0.7f; assert(tp_zone_hold(&e));
    e.type=SDL_EVENT_FINGER_CANCELED; assert(touchpad_event(&e)); assert(!window_touch_look_delta(&dx,&dy));
    rb_held=1; e=start_look(83); e.type=SDL_EVENT_FINGER_MOTION; e.tfinger.x=0.7f;
    assert(!tp_zone_hold(&e) && !tl_active); rb_held=0;
    game_gesture=1; e=start_look(84); e.type=SDL_EVENT_FINGER_MOTION; e.tfinger.x=0.7f;
    assert(!tp_zone_hold(&e) && !tl_active); game_gesture=0;
    game_twist=1; e=start_look(85); e.type=SDL_EVENT_FINGER_MOTION; e.tfinger.x=0.7f;
    assert(!tp_zone_hold(&e) && !tl_active); game_twist=0;
    e=start_look(86); e.type=SDL_EVENT_FINGER_MOTION; e.tfinger.x=0.7f; assert(tp_zone_hold(&e));
    menu=1; assert(!window_touch_look_delta(&dx,&dy)); window_clear_input(); menu=0;
    assert(!window_touch_look_delta(&dx,&dy) && !tl_active);
    e=start_look(87); e.type=SDL_EVENT_FINGER_MOTION; e.tfinger.x=0.7f; assert(tp_zone_hold(&e));
    input_focused=0; assert(!window_touch_look_delta(&dx,&dy)); window_clear_input(); input_focused=1;
    assert(!window_touch_look_delta(&dx,&dy) && !tl_active);
    values[5]=0; clock_ns+=1000000000; assert(!tl_want());
    e=finger(SDL_EVENT_FINGER_DOWN,88,0.99f,0.7f); assert(!tp_zone_hold(&e));
    clock_ns+=200000000; tp_zone_tick(); assert(tv.sr_active); touchpad_cancel_all();
    values[5]=1; unsetenv("RECOMP_TOUCH_LOOK"); clock_ns+=1000000000;
    assert(!tl_want()); /* a global preference cannot enable unsupported packs */
    setenv("RECOMP_TOUCH_LOOK","1",1); clock_ns+=1000000000;
    puts("PASS: direct touch distance, first motion, final lift, no drift, exclusive finger, 30/60 fps, sensitivity, puzzle routing and cancellation");
}
static int look_stop;
static int64_t look_sum_x,look_sum_y;
static void *read_look(void *unused) {
    (void)unused;
    do {
        float dx,dy; window_touch_look_delta(&dx,&dy);
        const double radians=3.14159265358979323846f/(1<<20);
        look_sum_x+=llround(dx/radians); look_sum_y+=llround(dy/radians);
    } while(!__atomic_load_n(&look_stop,__ATOMIC_ACQUIRE));
    return NULL;
}
static void look_publication(void) {
    touchpad_cancel_all(); tl_lx=tl_ly=0;
    pthread_t reader; assert(!pthread_create(&reader,NULL,read_look,NULL));
    for(int i=1;i<=100000;i++) {
        const float point=(float)i*tv.w/(1<<20);
        tl_move(point,-point);
    }
    __atomic_store_n(&look_stop,1,__ATOMIC_RELEASE); pthread_join(reader,NULL);
    read_look(NULL); /* one final drain after the writer stops */
    assert(look_sum_x==100000 && look_sum_y==-100000);
    puts("PASS: 100,000 concurrent direct-look publications preserve both axes without loss or duplication");
}
static float guest_float(uint32_t address) { uint32_t bits=RD32(address); float f; memcpy(&f,&bits,4); return f; }
static void camera_hook(void) {
    Cpu c={0}; c.r[6]=0x100; c.r[0]=0x600;
    raw_mouse=0; mouse_sens=9; invert_mouse=1;
    SDL_Event e=start_look(90); e.type=SDL_EVENT_FINGER_MOTION; e.tfinger.x=0.7f; e.tfinger.y+=0.1f;
    assert(tp_zone_hold(&e)); recomp_ihook_uc_mouse_look(&c,0); recomp_ihook_uc_look_velocity(&c,0);
    close_to(guest_float(0x760),0.1f*3.14159265f);
    close_to(guest_float(0x764),0.1f*tv.h/tv.w*3.14159265f);
    WR32(0x760,0); WR32(0x764,0);
    recomp_ihook_uc_mouse_look(&c,0); recomp_ihook_uc_look_velocity(&c,0);
    assert(!RD32(0x760) && !RD32(0x764)); /* consumed exactly once, no stationary continuation */
    for(int i=0;i<10;i++) recomp_ihook_uc_mouse_look(&c,0);
    e.tfinger.x+=0.01f; assert(touchpad_event(&e));
    recomp_ihook_uc_mouse_look(&c,0);
    recomp_ihook_uc_mouse_look(&c,0); recomp_ihook_uc_mouse_look(&c,0);
    recomp_ihook_uc_look_velocity(&c,0);
    close_to(guest_float(0x760),0.01f*3.14159265f); /* a fresh batch gets its own age after idle */
    WR32(0x760,0); WR32(0x764,0);
    e.tfinger.x+=0.01f; assert(touchpad_event(&e)); recomp_ihook_uc_mouse_look(&c,0);
    for(int i=0;i<6;i++) recomp_ihook_uc_mouse_look(&c,0);
    recomp_ihook_uc_look_velocity(&c,0); assert(!RD32(0x760) && !RD32(0x764)); /* stale cutscene input expires */
    touchpad_cancel_all(); raw_mouse=1; mouse_sens=2;
    mouse_dx_q8=512; mouse_dy_q8=-256;
    recomp_ihook_uc_mouse_look(&c,0); recomp_ihook_uc_look_velocity(&c,0);
    close_to(guest_float(0x760),0.006f); close_to(guest_float(0x764),0.003f);
    puts("PASS: production Uncharted touch-to-camera hooks preserve exact yaw/pitch and retain desktop mouse scaling/invert");
}
int main(void) { geometry(); input(); holds(); publication(); focus(); direct_look(); look_publication(); camera_hook(); return 0; }
'''
with tempfile.TemporaryDirectory(prefix='nativ-touchpad-') as folder:
    source = Path(folder) / 'test.c'
    binary = Path(folder) / 'test'
    source.write_text(ADAPTERS + RELEASE + CONTACTS + MOUSE + PAD + WINDOW_INPUT + CLEAR + HOOKS + TESTS, encoding='utf-8')
    command = [os.environ.get('CC', 'cc'), '-std=c11', '-D_POSIX_C_SOURCE=200809L', '-O1', '-g', '-Wall', '-Wextra', '-Werror',
               '-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-I', str(ROOT / 'runtime/ui'),
               str(source), '-lm', '-pthread', '-o', str(binary)]
    subprocess.run(command, check=True)
    test_env = os.environ.copy()
    for key in ('RECOMP_TOUCHPAD', 'RECOMP_TOUCHPAD_RSTICK', 'RECOMP_STICK_HOLD', 'RECOMP_STICK_DRAG', 'RECOMP_TOUCH_LOOK', 'RECOMP_YAW_DIAG'):
        test_env.pop(key, None)
    subprocess.run([str(binary)], check=True, env=test_env)
