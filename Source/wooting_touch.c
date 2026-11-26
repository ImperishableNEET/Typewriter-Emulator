// Windows x64. Build with gcc -O2 -Wall -Wextra -s -o GodivaStudio/assets/wooting-touch.bin Source/wooting_touch.c -lwinmm
#define _WIN32_WINNT 0x0602
#include <windows.h>
#include <mmsystem.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

typedef struct { float depth; double last, start; int armed; } Travel;
typedef struct { uint32_t hid; float speed; double unix_ms; } Packet;
_Static_assert(sizeof(Packet) == 16, "pipe packet layout");
// Normal HID packets carry one downstroke speed. Tagged packets carry a
// current position for controls with continuous mechanical travel.
#define POSITION_PACKET 0x10000u
static int reports_position(unsigned hid) {
    return (hid>=4 && hid<=39) || (hid>=42 && hid<=56) ||
           (hid>=84 && hid<=87) || (hid>=89 && hid<=99) ||
           hid==225 || hid==229;
}

// Measure travel between two depths. Interpolate threshold crossing times
// so a fast stroke which crosses both thresholds in one poll still registers.
static float downstroke(Travel *k, float depth, double now) {
    const float low = .06f, high = .32f;
    float speed = 0, rise = depth - k->depth;
    double dt = now - k->last;
    if (dt <= 0 || dt > 12) k->armed = 0;
    else if (rise > 0) {
        if (k->depth < low && depth >= low) {
            k->start = k->last + dt * (low - k->depth) / rise;
            k->armed = 1;
        }
        if (k->armed && depth >= high) {
            double end = k->last + dt * (high - k->depth) / rise;
            if (end > k->start) speed = (float)(1000 * (high - low) / (end - k->start));
            k->armed = 0;
        }
    }
    if (depth < low) k->armed = 0;
    k->depth = depth;
    k->last = now;
    return speed;
}

static int emit(uint32_t hid, float speed) {
    FILETIME ft;
    GetSystemTimePreciseAsFileTime(&ft);
    ULARGE_INTEGER ticks = {.LowPart=ft.dwLowDateTime, .HighPart=ft.dwHighDateTime};
    Packet p = {hid, speed, (ticks.QuadPart - 116444736000000000ULL) / 10000.0};
    DWORD written;
    return WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), &p, sizeof(p), &written, NULL) && written == sizeof(p);
}

int main(int argc, char **argv) {
    if (argc == 2 && !strcmp(argv[1], "--self-test")) {
        Travel slow = {0}, fast = {0};
        downstroke(&slow, 0, 100); downstroke(&fast, 0, 100);
        downstroke(&slow, .1f, 105); downstroke(&slow, .2f, 110);
        float s = downstroke(&slow, .4f, 120), f = downstroke(&fast, .4f, 102);
        return !(fabsf(s-20)<.01 && fabsf(f-200)<.01 && downstroke(&fast,.8f,104)==0
            && downstroke(&fast,0,106)==0 && downstroke(&fast,.6f,108)>f
            && downstroke(&slow,0,125)==0 && downstroke(&slow,.6f,150)==0);
    }
    if (argc != 2) return 1;
    DWORD owner = strtoul(argv[1], NULL, 10);
    HANDLE parent = OpenProcess(SYNCHRONIZE, FALSE, owner);
    if (!parent) return 1;
    wchar_t folder[MAX_PATH], path[MAX_PATH];
    DWORD length = GetEnvironmentVariableW(L"GODIVA_WOOTING_SDK_DIR", folder, MAX_PATH);
    const wchar_t *format = L"%ls\\wooting_analog_sdk.dll";
    if (!length) {
        length = GetEnvironmentVariableW(L"ProgramFiles", folder, MAX_PATH);
        format = L"%ls\\wooting-analog-sdk\\wooting_analog_sdk.dll";
    }
    if (!length || length >= MAX_PATH || swprintf(path, MAX_PATH, format, folder) < 0) return 2;
    HMODULE sdk = LoadLibraryExW(path, NULL, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
    if (!sdk) return 2;
    typedef int (*Init)(void);
    typedef int (*ReadKeys)(unsigned short *, float *, unsigned int);
    Init init = (Init)(void*)GetProcAddress(sdk, "wooting_analog_initialise");
    Init close_sdk = (Init)(void*)GetProcAddress(sdk, "wooting_analog_uninitialise");
    ReadKeys read_keys = (ReadKeys)(void*)GetProcAddress(sdk, "wooting_analog_read_full_buffer");
    if (!init || !close_sdk || !read_keys || init() < 0) return 3;
    Travel keys[256] = {0};
    LARGE_INTEGER frequency;
    QueryPerformanceFrequency(&frequency);
    int connected = -1, tracking = 0;
    float sent_depth[232] = {0};
    timeBeginPeriod(1);
    while (WaitForSingleObject(parent, connected==1 && tracking ? 1 : 40) == WAIT_TIMEOUT) {
        unsigned short codes[256];
        float values[256], depths[256] = {0};
        int n = read_keys(codes, values, 256);
        if (n < 0 && n != -1999) break; // SDK NoDevices allows hot-plug.
        if ((n >= 0) != connected) {
            connected = n >= 0;
            if (!emit(0, (float)connected)) break;
        }
        DWORD foreground = 0;
        GetWindowThreadProcessId(GetForegroundWindow(), &foreground);
        int active = connected && foreground == owner;
        if (!active) {
            if (tracking) for (unsigned i=4;i<232;++i)
                if (sent_depth[i]>0.f && !emit(POSITION_PACKET|i,-1.f)) goto done;
            memset(sent_depth,0,sizeof(sent_depth));
            tracking = 0;
            continue;
        }
        for (int i=0; i<n; ++i) if (codes[i]<256) depths[codes[i]]=values[i];
        for (unsigned hid=4;hid<232;++hid) {
            if (!reports_position(hid)) continue;
            float depth=depths[hid];
            if (fabsf(depth-sent_depth[hid])>=.012f || (depth==0.f && sent_depth[hid]!=0.f)) {
                if (!emit(POSITION_PACKET|hid,depth)) goto done;
                sent_depth[hid]=depth;
            }
        }
        LARGE_INTEGER tick;
        QueryPerformanceCounter(&tick);
        double now = tick.QuadPart * 1000.0 / frequency.QuadPart;
        for (unsigned i=4; i<232; ++i) {
            if (!tracking) keys[i]=(Travel){.depth=depths[i],.last=now};
            else {
                float speed = downstroke(&keys[i], depths[i], now);
                if (speed > 0 && !emit(i, speed)) goto done;
            }
        }
        tracking = 1;
    }
done:
    timeEndPeriod(1);
    close_sdk();
    CloseHandle(parent);
    return 0;
}
