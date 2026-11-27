// The phone's own motion sensor as the Vita's (iOS): CoreMotion's accelerometer and
// gyroscope, rotated from the device's frame into the game screen's landscape frame, fed
// to the same motion.c path a gyro pad's samples take. A phone held in landscape IS the
// Vita -- the samples land in its screen frame already, so motion.c's pose mapping doesn't
// apply (its "native" source) and the gyroscope setting gates it exactly as a pad's.
//
// CoreMotion reports the accelerometer in g, as the gravity vector at rest (flat, screen
// up: (0, 0, -1)) -- motion.c takes SDL's convention (specific force in m/s^2, at rest
// +9.8 along "up"), so the sample is negated and scaled. The gyro is rad/s in both, and
// both frames are right-handed, so it only needs the rotation.
//
// The device frame is portrait-based (+x right, +y at the earpiece, +z out of the screen);
// the game's screen frame is landscape (+x right on the screen, +y up the screen, +z out).
// Which landscape is playing is the interface orientation, handed over by the chrome's
// main-thread window sync:
//   home on the left  (LandscapeLeft):  x_s = +y_d, y_s = -x_d
//   home on the right (LandscapeRight): x_s = -y_d, y_s = +x_d
// Both are proper rotations, so the gyro turns with the same sign the phone was turned.

#import <Foundation/Foundation.h>
#import <CoreMotion/CoreMotion.h>
#include <stdint.h>
#include <stdio.h>

extern void motion_feed_accel(const float s[3], uint64_t t_ns);
extern void motion_feed_gyro(const float s[3], uint64_t t_ns);
extern void motion_source_native(int on);

static CMMotionManager *fxmgr;
static NSOperationQueue *fxq;
static int fxstarted, fxlogged;
static volatile int fxorient = 3;      /* UIInterfaceOrientationLandscapeLeft: the game's own */
static volatile int fxhold;            /* a physical gyro pad has the source: the phone stands down */

void ios_motion_orient(int o) { if (o) fxorient = o; }

int ios_motion_present(void) { return fxstarted && !fxhold; }

/* a gyro pad in hand takes the source; its removal gives it back (window.c calls this) */
void ios_motion_hold(int on) {
    fxhold = (on != 0);
    motion_source_native(!fxhold && fxstarted);
}

int ios_motion_start(void) {
    if (fxstarted) return 1;
    CMMotionManager *m = [[CMMotionManager alloc] init];
    if (!m.isAccelerometerAvailable || !m.isGyroAvailable) { [m release]; return 0; }
    NSOperationQueue *q = [[NSOperationQueue alloc] init];
    fxmgr = m; fxq = q;                 /* app-lifetime objects, like the rest of the chrome */
    m.accelerometerUpdateInterval = 1.0 / 60.0;
    m.gyroUpdateInterval = 1.0 / 60.0;
    [m startAccelerometerUpdatesToQueue:q withHandler:^(CMAccelerometerData *d, NSError *e) {
        if (!d || fxhold || !fxstarted) return;
        const float x = (float)d.acceleration.x, y = (float)d.acceleration.y, z = (float)d.acceleration.z;
        float a[3];
        if (fxorient == 4) { a[0] = -y; a[1] = x; a[2] = z; }     /* LandscapeRight: home on the right */
        else               { a[0] =  y; a[1] = -x; a[2] = z; }     /* LandscapeLeft (and anything else) */
        float s[3] = { -9.80665f * a[0], -9.80665f * a[1], -9.80665f * a[2] };
        motion_feed_accel(s, (uint64_t)(d.timestamp * 1e9));
    }];
    [m startGyroUpdatesToQueue:q withHandler:^(CMGyroData *d, NSError *e) {
        if (!d || fxhold || !fxstarted) return;
        const float x = (float)d.rotationRate.x, y = (float)d.rotationRate.y, z = (float)d.rotationRate.z;
        float g[3];
        if (fxorient == 4) { g[0] = -y; g[1] = x; g[2] = z; }
        else               { g[0] =  y; g[1] = -x; g[2] = z; }
        motion_feed_gyro(g, (uint64_t)(d.timestamp * 1e9));
    }];
    fxstarted = 1;
    motion_source_native(1);
    if (!fxlogged) { fxlogged = 1; fprintf(stderr, "    motion: the phone's own gyroscope and accelerometer are the Vita's sensor (CoreMotion, 60 Hz)\n"); }
    return 1;
}
