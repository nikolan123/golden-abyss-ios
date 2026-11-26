#!/usr/bin/env python3
"""Run the production native overlay state machine without UIKit or a GPU."""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'runtime/ui/overlay.cpp').read_text(encoding='utf-8')
lifecycle = source[source.index('int overlay_init('):source.index('static int g_rebind = -1;')]
choose = source[source.index('static void layout_choose(int v) {'):source.index('static void build_layout(void) {')]
state = source[source.index('extern "C" void overlay_native_state('):source.index('extern "C" int overlay_layout_ask(void)')]
frame_start = source.index('void overlay_frame(SDL_GPUCommandBuffer *cmd')
frames = source[frame_start:source.index('/* RECOMP_OVERLAY_DUMP', frame_start)]
frames = frames.replace('#if defined(__APPLE__) && defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE', '#if 1')
prefix = r'''
#include <atomic>
#include <cassert>
#include <cstring>
#include <cstdio>
#include <cstdint>
#include "overlay_native.h"
static void *g_ctx=(void*)1;
static bool g_has_window=true,g_toast_checked,g_layout_card,g_layout_remember;
static std::atomic<bool> g_open,g_intro,g_prep_card,g_quit_card,g_paused,g_want_quit;
static std::atomic<int> g_native_card_seq,g_layout_ask,g_layout_answer;
static int prep,paused,remembered,toasts,dialog,intro_stored=1;
static int settings_has(const char*) { return intro_stored; }
static void settings_set_int(const char *key,int value) { assert(!strcmp(key,"controller_layout")); remembered=value; }
static void settings_save() {}
static void apply_pause() { paused=g_open || g_paused; }
static int overlay_dialog_active() { return dialog; }
static int gfx_gpu_shader_prep(int *done,int *total,double *eta) {
    *done=20; *total=100; *eta=10; int value=prep; if(prep==3) prep=0; return value;
}
static void overlay_toast_titled(const char*,const char*,double) { toasts++; }
static void overlay_close() {
    if(g_prep_card) prep=2;
    g_prep_card=false; g_quit_card=false; g_layout_card=false;
    g_open=false; g_paused=false; apply_pause();
}
struct SDL_GPUCommandBuffer {};
struct SDL_GPUTexture {};
struct OverlayMark { float x,y; int rear,pressed,cursor; };
static bool native_mode=true;
static int rendered,native_marks,g_nosd,g_nmarks;
static char g_osd[7][40]; static float g_rear[4]; static const OverlayMark *g_marks;
static bool ios_ui_chrome_active() { return native_mode; }
extern "C" void ios_ui_chrome_marks(const void*,int,const float[4]) { native_marks++; }
static bool overlay_is_open() { return g_open; }
static int metrics_osd_lines(char[][40],int) { return 0; }
static void build_quit() {} static void build_layout() {} static void build_prep() {} static void build_ui() {} static void build_closed() {}
static void render_frame(SDL_GPUCommandBuffer*,SDL_GPUTexture*,uint32_t,uint32_t,double,bool,void(*)(void)) { rendered++; }
'''
tests = r'''
int main() {
    NativeOverlayState s;
    overlay_native_state(&s); assert(!s.kind && !paused);
    g_layout_ask=1; overlay_native_state(&s);
    assert(s.kind==NATIVE_CARD_LAYOUT && paused);
    overlay_native_answer(s.kind,s.seq-1,2,1); assert(g_layout_card && !remembered);
    overlay_native_answer(s.kind,s.seq,2,1);
    assert(!g_layout_card && g_layout_answer==2 && remembered==2 && !paused);
    prep=1; dialog=1; overlay_native_state(&s);
    assert(!s.kind && !paused); // never pause a running game-owned dialog for preparation
    dialog=0; overlay_native_state(&s); assert(s.kind==NATIVE_CARD_PREP && paused);
    overlay_native_answer(s.kind,s.seq,0,0); assert(prep==2 && !paused);
    overlay_native_state(&s); assert(!s.kind && s.prep_state==2);
    prep=3; overlay_native_state(&s); assert(toasts==1 && !s.kind);
    overlay_native_state(&s); assert(toasts==1);
    prep=1; overlay_native_state(&s); assert(g_prep_card && paused);
    g_quit_card=true; ++g_native_card_seq; prep=3;
    overlay_native_state(&s); assert(s.kind==NATIVE_CARD_QUIT && paused && !g_prep_card);
    overlay_native_answer(s.kind,s.seq-1,1,0); assert(!g_want_quit);
    overlay_native_answer(s.kind,s.seq,0,0); assert(!g_quit_card && !paused);
    g_quit_card=true; g_open=true; ++g_native_card_seq; apply_pause();
    overlay_native_state(&s); overlay_native_answer(s.kind,s.seq,1,0); assert(g_want_quit);
    g_want_quit=false; overlay_close();
    intro_stored=0; g_toast_checked=false; prep=1;
    overlay_native_state(&s); assert(g_intro && !s.kind && !paused);
    g_intro=false; overlay_native_state(&s); assert(s.kind==NATIVE_CARD_PREP && paused);
    overlay_frame(nullptr,nullptr,932,430,0.016); overlay_marks(nullptr,nullptr,932,430,0.016,nullptr,0,nullptr);
    assert(!rendered && native_marks==1); // the normal native path never constructs an ImGui frame
    native_mode=false; overlay_frame(nullptr,nullptr,932,430,0.016); assert(rendered==1);
    g_open=false; overlay_marks(nullptr,nullptr,932,430,0.016,nullptr,0,nullptr); assert(rendered==2);
    puts("PASS: native intro, controller choice, saved preference, stale replies, prep skip/completion, dialog priority and quit state");
}
'''
lifecycle_prefix = r'''
#include <cassert>
#include <cstdio>
#define IMGUI_CHECKVERSION() ((void)0)
struct SDL_GPUDevice {};
struct SDL_Window {};
using SDL_GPUTextureFormat = int;
enum { SDL_GPU_SAMPLECOUNT_1=1 };
struct ImGuiContext {};
struct ImGuiIO { const char *IniFilename="imgui.ini"; };
static ImGuiContext context;
static ImGuiIO io;
static int created,destroyed,fonts,styled,platform_init,gpu_init,platform_stop,gpu_stop;
static bool native_mode=true,platform_ok=true,gpu_ok=true;
namespace ImGui {
static ImGuiContext *CreateContext() { created++; io.IniFilename="imgui.ini"; return &context; }
static void DestroyContext(ImGuiContext *p) { assert(p==&context); destroyed++; }
static void SetCurrentContext(ImGuiContext *p) { assert(p==&context); }
static ImGuiIO &GetIO() { return io; }
}
namespace ui { static void load_system_font(ImGuiIO&) { fonts++; } }
static void style_sync() { styled++; }
static bool ios_ui_chrome_active() { return native_mode; }
static bool ImGui_ImplSDL3_InitForSDLGPU(SDL_Window*) { platform_init++; return platform_ok; }
static void ImGui_ImplSDL3_Shutdown() { platform_stop++; }
struct ImGui_ImplSDLGPU3_InitInfo { SDL_GPUDevice *Device; int ColorTargetFormat,MSAASamples; };
static bool ImGui_ImplSDLGPU3_Init(ImGui_ImplSDLGPU3_InitInfo*) { gpu_init++; return gpu_ok; }
static void ImGui_ImplSDLGPU3_Shutdown() { gpu_stop++; }
static ImGuiContext *g_ctx;
static SDL_Window *g_window;
static bool g_has_window,g_native_context_only,g_open,g_want_quit,g_want_capture,g_paused;
static float g_style_em;
'''
lifecycle_tests = r'''
int main() {
    SDL_GPUDevice device; SDL_Window window;
    assert(!overlay_init(nullptr,&window,0) && !created);
    assert(overlay_init(&device,&window,0));
    assert(g_native_context_only && g_has_window && g_window==&window && !io.IniFilename);
    assert(!fonts && !styled && !platform_init && !gpu_init);
    assert(overlay_init(&device,&window,0) && created==1);
    overlay_shutdown(); overlay_shutdown();
    assert(destroyed==1 && !platform_stop && !gpu_stop && !g_ctx);
    native_mode=false;
    assert(overlay_init(&device,&window,0));
    assert(fonts==1 && styled==1 && platform_init==1 && gpu_init==1);
    overlay_shutdown(); assert(platform_stop==1 && gpu_stop==1);
    assert(overlay_init(&device,nullptr,0) && !g_has_window);
    overlay_shutdown(); assert(platform_stop==1 && gpu_stop==2);
    platform_ok=false;
    assert(!overlay_init(&device,&window,0) && !g_ctx);
    platform_ok=true; gpu_ok=false;
    assert(!overlay_init(&device,&window,0) && !g_ctx && platform_stop==2);
    assert(created==destroyed);
    puts("PASS: native initialization skips fonts/platform/GPU backends; shutdown, legacy and failed initialization balance");
}
'''

for name, program in (
    ('state', prefix+choose+state+frames+tests),
    ('lifecycle', lifecycle_prefix+lifecycle+lifecycle_tests),
):
    with tempfile.TemporaryDirectory(prefix='nativ-overlay-') as folder:
        path=Path(folder)/(name+'.cpp')
        binary=Path(folder)/name
        path.write_text(program,encoding='utf-8')
        subprocess.run([os.environ.get('CXX','c++'),'-std=c++17','-Wall','-Wextra','-Werror','-fsanitize=address,undefined',
                        '-I',str(root/'runtime/ui'),str(path),'-o',str(binary)],check=True)
        subprocess.run([str(binary)],check=True)
