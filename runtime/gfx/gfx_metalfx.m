// Present-time MetalFX upscaling (iOS): the game renders at 1x (960x544) and Apple's
// MetalFX spatial scaler does the one upscale here, at present, into the letterbox rect
// on the swapchain -- the 2x render path costs 4x pixels for the whole frame, this costs
// one spatial pass at output size. RECOMP_METALFX=1 enables it; every fallback (no
// MetalFX, unsupported device, odd source rect) lands back on the plain present path.
//
// The scaler rides SDL's own command buffer: the raw Metal objects behind SDL GPU
// wrappers come from the three SDL_METAL_* interop exports nativ's SDL patch adds
// (src/gpu/metal/SDL_gpu_metal.m) -- they are not SDL API and exist in the nativ-built
// libSDL3.a alone.

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include "SDL3/SDL_gpu.h"

#if defined(__ENVIRONMENT_IPHONE_OS_VERSION_MIN_REQUIRED__) || defined(IOS)

#import <MetalFX/MetalFX.h>

// nativ's SDL patch (not SDL API)
extern void *SDL_METAL_TextureHandle(SDL_GPUTexture *texture);
extern void *SDL_METAL_DeviceHandle(SDL_GPUDevice *device);
extern void *SDL_METAL_CommandBufferHandle(SDL_GPUCommandBuffer *commandBuffer);

static id<MTLDevice> fxdev = nil;
static id<MTLFXSpatialScaler> fxscaler = nil;
static SDL_GPUTexture *fxout = nil;
static uint32_t fxin_w, fxin_h, fxout_w, fxout_h;   // what fxscaler/fxout are sized for now
static int fx_failed = 0, fx_logged = 0;

static void fx_log(const char *fmt, ...) { va_list a; va_start(a, fmt); fputs("    metalfx: ", stderr); vfprintf(stderr, fmt, a); va_end(a); fputc('\n', stderr); }

/* the Display page's "MetalFX upscaling" switch: a saved choice wins, RECOMP_METALFX
 * (the pack's RUN_ENV) is the default, and the toggle takes effect the same frame */
static int metalfx_wanted(void)
{
    extern int settings_int(const char *key, int def);
    const char *e = getenv("RECOMP_METALFX");
    return settings_int("metalfx", e && *e && *e != '0');
}

// The scaler (and its output texture) rebuilt for a new input or output size; the
// swapchain's pixel size changes with rotation, the input with the render scale.
static int fx_rebuild(SDL_GPUDevice *gpu, uint32_t sw, uint32_t sh, uint32_t dw, uint32_t dh)
{
    if (@available(iOS 16, *)) {
        void *dh_ = SDL_METAL_DeviceHandle(gpu);
        if (!dh_) { fx_log("no Metal device handle (is the driver metal?)"); fx_failed = 1; return 0; }
        fxdev = (__bridge id<MTLDevice>)dh_;
        if (![MTLFXSpatialScalerDescriptor respondsToSelector:@selector(supportsDevice:)] || ![MTLFXSpatialScalerDescriptor supportsDevice:fxdev]) {
            fx_log("this GPU does not support MetalFX spatial scaling"); fx_failed = 1; return 0;
        }
        MTLFXSpatialScalerDescriptor *d = [[MTLFXSpatialScalerDescriptor alloc] init];
        d.colorTextureFormat = MTLPixelFormatRGBA8Unorm;    // the game frame textures (unorm, display-ready values)
        d.outputTextureFormat = MTLPixelFormatBGRA8Unorm;   // the SDR swapchain's own format: the last blit is a raw copy
        d.inputWidth = sw;  d.inputHeight = sh;
        d.outputWidth = dw; d.outputHeight = dh;
        d.colorProcessingMode = MTLFXSpatialScalerColorProcessingModePerceptual;   // the values in those unorm textures are sRGB-encoded
        id<MTLFXSpatialScaler> s = [d newSpatialScalerWithDevice:fxdev];
        [d release];
        if (!s) { fx_log("scaler creation refused (%ux%u -> %ux%u)", sw, sh, dw, dh); fx_failed = 1; return 0; }
        fxscaler = s;   // (the previous one leaks once per resize: app-lifetime objects, rotations are rare)
        if (fxout) { SDL_ReleaseGPUTexture(gpu, fxout); fxout = nil; }
        SDL_GPUTextureCreateInfo ci = { .type = SDL_GPU_TEXTURETYPE_2D, .width = dw, .height = dh,
                                        .format = SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM,
                                        .usage = SDL_GPU_TEXTUREUSAGE_SAMPLER | SDL_GPU_TEXTUREUSAGE_COMPUTE_STORAGE_WRITE };
        fxout = SDL_CreateGPUTexture(gpu, &ci);
        if (!fxout) { fx_log("output texture (%ux%u) failed", dw, dh); fxscaler = nil; fx_failed = 1; return 0; }
        fxin_w = sw; fxin_h = sh; fxout_w = dw; fxout_h = dh;
        return 1;
    }
    fx_failed = 1;
    return 0;
}

int metalfx_present(SDL_GPUDevice *gpu, SDL_GPUCommandBuffer *cmd, SDL_GPUTexture *src,
                    uint32_t sw, uint32_t sh, SDL_GPUTexture *swap,
                    uint32_t dx, uint32_t dy, uint32_t dw, uint32_t dh)
{
    if (!fx_logged && metalfx_wanted()) { fx_logged = 1; fx_log("on (present-time spatial upscale)"); }
    if (!metalfx_wanted() || fx_failed || !gpu || !cmd || !src || !swap || !sw || !sh || dw < sw || dh < sh)
        return 0;   // off, broken, or nothing to upscale (framegen's frames already land at window size)
    if (!fxscaler || fxin_w != sw || fxin_h != sh || fxout_w != dw || fxout_h != dh)
        if (!fx_rebuild(gpu, sw, sh, dw, dh)) return 0;
    void *src_h = SDL_METAL_TextureHandle(src), *out_h = SDL_METAL_TextureHandle(fxout), *cb_h = SDL_METAL_CommandBufferHandle(cmd);
    if (!src_h || !out_h || !cb_h) { if (!fx_failed) fx_log("missing native handles -- off"); fx_failed = 1; return 0; }
    fxscaler.colorTexture = (__bridge id<MTLTexture>)src_h;
    fxscaler.outputTexture = (__bridge id<MTLTexture>)out_h;
    fxscaler.inputContentWidth = sw;
    fxscaler.inputContentHeight = sh;
    [fxscaler encodeToCommandBuffer:(__bridge id<MTLCommandBuffer>)cb_h];
    // the upscaled picture onto the swapchain, in the same letterbox rect the plain
    // blit uses; LOAD clears the bars around it to black
    SDL_GPUBlitInfo blit = {
        .source = { .texture = fxout, .x = 0, .y = 0, .w = dw, .h = dh },
        .destination = { .texture = swap, .x = dx, .y = dy, .w = dw, .h = dh },
        .load_op = SDL_GPU_LOADOP_CLEAR, .clear_color = { 0, 0, 0, 1 }, .filter = SDL_GPU_FILTER_LINEAR,
    };
    SDL_BlitGPUTexture(cmd, &blit);
    return 1;
}

#else   // not iOS: the plain present path, always

int metalfx_present(SDL_GPUDevice *gpu, SDL_GPUCommandBuffer *cmd, SDL_GPUTexture *src,
                    uint32_t sw, uint32_t sh, SDL_GPUTexture *swap,
                    uint32_t dx, uint32_t dy, uint32_t dw, uint32_t dh)
{ (void)gpu; (void)cmd; (void)src; (void)sw; (void)sh; (void)swap; (void)dx; (void)dy; (void)dw; (void)dh; return 0; }

#endif
