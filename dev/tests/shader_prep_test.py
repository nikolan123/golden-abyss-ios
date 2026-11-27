#!/usr/bin/env python3
"""Exercise production recipe loading and startup preparation without a GPU.

The actual loader reads the shipped pack recipes, including Windows checkouts.
The actual preparation functions run against deterministic clock/worker adapters.
Run: python3 dev/tests/shader_prep_test.py (C compiler and sanitizers required).
"""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'runtime/gfx/gfx_gpu.c').read_text(encoding='utf-8')


def section(start, end):
    pos = source.index(start)
    return source[pos:source.index(end, pos)]


common = r'''
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
'''
parser_prefix = common + r'''
#include "usse_spirv.h"
typedef struct { int unused; } ShaderEntry;
static const char *local_path;
static const char *recipes_file(void) { return local_path; }
static int canon_vary_on(void) { return 1; }
static int predict_on(void) { return 0; }
static const char *shader_cache_dir(void) { return NULL; }
static void warm_open(const char *path) { (void)path; }
static void prep_begin(void) {}
static int prep_blocking(void) { return 0; }
const char *host_app0(void) { return "."; }
static void gxp_index_start(const char *app, const char *cache, const uint32_t *want, int n) {
    (void)app; (void)cache; (void)want; (void)n;
}
'''
parser = (
    parser_prefix
    + section('#define HASH_STEP', 'static uint64_t gpu_frame_no;')
    + section('#define RECIPES_HEADER', 'static const char *recipes_file(')
    + section('#define RC_SET', '/* an S line\'s text')
    + section('static int parse_sa(', 'static void rc_registered(')
    + r'''
int main(int argc, char **argv) {
    assert(argc==5);
    setenv("RECOMP_SHADER_RECIPES_SHIPPED",argv[1],1); local_path=argv[2];
    recipes_load();
    assert(rc.state==1 && rc.nr==atoi(argv[3]) && rc.np==atoi(argv[4]));
    if (rc.fd>=0) close(rc.fd);
    free(rc.r); free(rc.p); free(rc.l); free(rc.prog); free(rc.use);
    return 0;
}
'''
)

prep_prefix = common + r'''
static int saved=-1, window=1, asynchronous=1, prediction=1;
static int settings_int(const char *key,int fallback) { assert(!strcmp(key,"shader_prep")); return saved<0 ? fallback : saved; }
static int window_active(void) { return window; }
static int gpu_async(void) { return asynchronous; }
static void *gpu(void) { return (void*)1; }
static uint64_t clock_us=1000000;
static uint64_t rc_us(void) { return clock_us; }
static pthread_mutex_t bq_m=PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t bq_c=PTHREAD_COND_INITIALIZER;
static int bq_workers=4,bq_low_cap=2,bq_bulk_cap=1<<30;
static uint32_t prep_built;
static struct { int w_need_sh,w_need_pp,warm_phase,pred_at,npst; uint64_t pred_t0; void *stand_vs; } rc;
static int archives,released,stepped;
static void warm_archive(void) { archives++; }
static void warm_unref(void *p) { assert(p); released++; }
static int predict_on(void) { return prediction; }
static int gxp_index_count(void) { return 10; }
static int pipe_predict_on(void) { return 0; }
static void pred_states(void) {}
static void *stand_in_vs(void) { return NULL; }
static void recipes_step(void) { stepped++; }
static int prep_blocking(void);
'''
prep = (
    prep_prefix
    + section('static int pred_low_cap', 'static void warm_archive(')
    + section('enum { PREP_OFF', 'static void recipes_warm_slice(uint64_t t0, uint64_t budget) {')
    + r'''
int main(int argc,char **argv) {
    assert(argc==3); saved=atoi(argv[1]); const char *test=argv[2];
    window=strcmp(test,"headless")!=0; asynchronous=strcmp(test,"sync")!=0;
    if (!strcmp(test,"lazy")) bq_workers=0;
    prediction=strcmp(test,"no-prediction")!=0;
    prep_begin();
    int done,total; double eta;
    if (prep_mode()==2 && window && asynchronous) {
        assert(prep_full && gfx_gpu_shader_prep(&done,&total,&eta)==1);
        assert(done==0 && total==0 && eta<0);
        if (!bq_workers) { prep_update(); assert(prep_reserve==-1 && bq_low_cap==2); bq_workers=4; }
        prep_update(); assert(bq_low_cap==4);
        const int early=!strcmp(test,"skip-index");
        if (early) { gfx_gpu_shader_prep_skip(); assert(bq_low_cap==2); }
        const int zero=!strcmp(test,"zero-recipes");
        rc.w_need_sh=zero ? 0 : 3; rc.w_need_pp=zero ? 0 : 2;
        if (!zero) prep_start();
        assert(gfx_gpu_shader_prep(&done,&total,&eta)==(early ? 2 : 1) && total==(zero ? 0 : 5));
        __atomic_store_n(&prep_built,5,__ATOMIC_RELAXED);
        warm_recipes_done(); assert(archives==1);
        if (prediction) {
            assert(rc.warm_phase==6 && prep_predicting);
            assert(gfx_gpu_shader_prep(&done,&total,&eta)==(early ? 2 : 1) && total==0 && eta<0);
            assert(bq_bulk_cap==(early ? 2 : 4));
            if (!strcmp(test,"skip-extra")) { gfx_gpu_shader_prep_skip(); assert(bq_bulk_cap==2 && bq_low_cap==2); }
            rc.stand_vs=(void*)1; warm_predictions_done(); assert(released==1);
        }
        assert(rc.warm_phase==5 && !prep_predicting && bq_low_cap==2 && bq_bulk_cap==(1<<30));
        assert(gfx_gpu_shader_prep(&done,&total,&eta)==3);
        assert(gfx_gpu_shader_prep(&done,&total,&eta)==0); // completion is consumed once
    } else {
        assert(!prep_full && prep_status()==PREP_OFF);
        rc.w_need_sh=3; rc.w_need_pp=2; prep_start();
        if (prep_mode() && window && asynchronous) {
            assert(prep_status()==PREP_MEASURE);
            clock_us+=9000000; prep_update(); assert(prep_status()==PREP_CARD);
            gfx_gpu_shader_prep_skip(); assert(prep_status()==PREP_BACKGROUND && bq_low_cap==2);
            prep_finish(); assert(gfx_gpu_shader_prep(&done,&total,&eta)==3);
        } else assert(gfx_gpu_shader_prep(&done,&total,&eta)==0);
    }
    puts("PASS: startup mode, worker limits, indexing/extra-pass Skip and completion");
}
'''
)

environment = os.environ.copy()
for key in ('RECOMP_SHADER_PREP', 'RECOMP_SHADER_PREP_SECS', 'RECOMP_SHADER_PREDICT_WORKERS', 'RECOMP_SHADER_LOADER'):
    environment.pop(key, None)

with tempfile.TemporaryDirectory(prefix='nativ-shader-prep-') as folder:
    temp = Path(folder)

    def compile_program(name, program, *extra):
        path = temp / (name + '.c')
        binary = temp / name
        path.write_text(program, encoding='utf-8')
        subprocess.run([os.environ.get('CC', 'cc'), '-std=c11', '-D_GNU_SOURCE', '-Wall', '-Wextra', '-Werror',
                        '-Wno-unused-function', '-fsanitize=address,undefined', '-g', '-I', str(root / 'runtime/gfx'),
                        *extra, str(path), '-pthread', '-o', str(binary)], check=True)
        return binary

    loader = compile_program('recipes', parser)
    raw = (root / 'packs/PCSA00029/shaders.txt').read_bytes()
    lines = raw.replace(b'\r\n', b'\n').splitlines()
    shaders = {line.split()[1]: line for line in lines if line.startswith(b'S ')}
    pipeline = next(line for line in lines if line.startswith(b'P '))
    vertex_id, fragment_id = pipeline.split()[1:3]
    fixture = b'\n'.join((lines[0], shaders[vertex_id], shaders[fragment_id], pipeline)) + b'\n'

    def load_case(name, shipped, local, shaders, pipelines):
        ship_path = temp / (name + '.shipped')
        local_path = temp / (name + '.local')
        ship_path.write_bytes(shipped)
        if local is not None:
            local_path.write_bytes(local)
        subprocess.run([str(loader), str(ship_path), str(local_path), str(shaders), str(pipelines)],
                       env=environment, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)

    expected_s = sum(line.startswith(b'S ') for line in raw.splitlines())
    expected_p = sum(line.startswith(b'P ') for line in raw.splitlines())
    assert expected_s > 0 and expected_p > 0
    load_case('shipped', raw, None, expected_s, expected_p)
    load_case('lf', fixture, None, 2, 1)
    load_case('crlf', fixture.replace(b'\n', b'\r\n'), None, 2, 1)
    load_case('mixed', fixture.replace(b'\n', b'\r\n', 2), None, 2, 1)
    load_case('dedup', fixture, fixture.replace(b'\n', b'\r\n'), 2, 1)
    load_case('version', fixture.replace(b'recipes 1', b'recipes 9'), None, 0, 0)
    load_case('incomplete', fixture.rstrip(b'\n'), None, 2, 0)
    bad_id = (b'0' if vertex_id[:1] != b'0' else b'1') + vertex_id[1:]
    load_case('bad-id', fixture.replace(b'S ' + vertex_id, b'S ' + bad_id, 1), None, 1, 0)
    print(f'PASS: actual shipped recipes ({expected_s} shaders/{expected_p} pipelines), LF/CRLF/mixed, dedup, version/hash and cut-short records')

    ios = compile_program('prep-ios', prep, '-DSDL_PLATFORM_IOS=1')
    desktop = compile_program('prep-desktop', prep)
    for mode, case in ((-1, 'hold'), (2, 'lazy'), (2, 'zero-recipes'), (2, 'skip-index'), (2, 'skip-extra'),
                       (2, 'no-prediction'), (0, 'background'), (1, 'automatic'), (2, 'headless'), (2, 'sync')):
        subprocess.run([str(ios), str(mode), case], env=environment, check=True)
    subprocess.run([str(desktop), '-1', 'automatic'], env=environment, check=True)
    for forced, saved in ((0, 2), (1, 2), (2, 0)):
        subprocess.run([str(ios), str(saved), 'hold'], env={**environment, 'RECOMP_SHADER_PREP': str(forced)}, check=True)
