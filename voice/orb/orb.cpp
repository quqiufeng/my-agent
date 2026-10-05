// voice/orb/orb.cpp — 桌面悬浮「球体」控制面板（SDL2）
//   · 无边框、置顶、可拖动
//   · 点球体 / 摄像头按钮 → 打开摄像头窗口 (voice.sh camera)
//   · 点音乐按钮 → 停掉后台播放并打开 VLC GUI，便于手动操作
//   · 右上角 × 或 ESC 退出
//
// 编译: make -C voice/orb
// 运行: voice/orb.sh

#include <SDL2/SDL.h>

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>
#include <unistd.h>

namespace {

constexpr int WIN_W = 176;
constexpr int WIN_H = 208;

constexpr int SPH_CX = WIN_W / 2;
constexpr int SPH_CY = 74;
constexpr int SPH_R  = 54;

constexpr int CAM_CX = 54, CAM_CY = 166, BTN_R = 23;
constexpr int MUS_CX = 122, MUS_CY = 166;

bool g_drag = false;
int  g_drag_dx = 0, g_drag_dy = 0;
bool g_moved = false;

Uint8 clamp8(double v) { return (Uint8)(v < 0 ? 0 : v > 255 ? 255 : v); }

// 用光照模型烘焙一个球体纹理（Lambert + 高光）
SDL_Texture *make_sphere(SDL_Renderer *ren, int R) {
    int S = R * 2;
    std::vector<Uint32> px(S * S, 0);
    // 光源方向（左上前）
    double Lx = -0.45, Ly = -0.62, Lz = 0.64;
    double Ln = std::sqrt(Lx * Lx + Ly * Ly + Lz * Lz); Lx /= Ln; Ly /= Ln; Lz /= Ln;
    double Hx = Lx, Hy = Ly, Hz = Lz + 1.0;  // 半程向量(V=(0,0,1))
    double Hn = std::sqrt(Hx * Hx + Hy * Hy + Hz * Hz); Hx /= Hn; Hy /= Hn; Hz /= Hn;
    double br = 0.22, bg = 0.56, bb = 0.98;   // 基色：青蓝
    double ar = 0.40, ag = 0.85, ab = 1.00;   // 环境色偏冷
    for (int y = 0; y < S; ++y) {
        for (int x = 0; x < S; ++x) {
            double nx = (x + 0.5 - R) / R;
            double ny = (y + 0.5 - R) / R;
            double d2 = nx * nx + ny * ny;
            if (d2 > 1.0) continue;
            double nz = std::sqrt(1.0 - d2);
            double diff = nx * Lx + ny * Ly + nz * Lz; if (diff < 0) diff = 0;
            double spec = nx * Hx + ny * Hy + nz * Hz; if (spec < 0) spec = 0;
            spec = std::pow(spec, 90.0) * 180.0;
            double base = 0.30 + 0.78 * diff;
            double fres = std::pow(1.0 - nz, 3.0) * 0.55;   // 边缘 Fresnel 提亮
            double r = br * base + ar * 0.10 + spec + fres * 0.25;
            double g = bg * base + ag * 0.10 + spec + fres * 0.55;
            double b = bb * base + ab * 0.10 + spec + fres * 1.00;
            // 边缘略暗，增强体积感
            double rim = 1.0 - 0.22 * d2;
            r *= rim; g *= rim; b *= rim;
            Uint8 R8 = clamp8(r * 255), G8 = clamp8(g * 255), B8 = clamp8(b * 255);
            px[y * S + x] = (0xFFu << 24) | ((Uint32)R8 << 16) | ((Uint32)G8 << 8) | B8;
        }
    }
    SDL_Texture *t = SDL_CreateTexture(ren, SDL_PIXELFORMAT_ARGB8888,
                                       SDL_TEXTUREACCESS_STATIC, S, S);
    SDL_UpdateTexture(t, nullptr, px.data(), S * sizeof(Uint32));
    return t;
}

void fill_circle(SDL_Renderer *ren, int cx, int cy, int r) {
    for (int y = -r; y <= r; ++y) {
        int dx = (int)std::sqrt((double)(r * r - y * y));
        SDL_RenderDrawLine(ren, cx - dx, cy + y, cx + dx, cy + y);
    }
}

void runbg(const std::string &cmd) {
    std::string full = "setsid sh -c '" + cmd + "' >/dev/null 2>&1 &";
    if (system(full.c_str()) == -1) fprintf(stderr, "[orb] launch failed: %s\n", cmd.c_str());
}

bool in_circle(int x, int y, int cx, int cy, int r) {
    int dx = x - cx, dy = y - cy; return dx * dx + dy * dy <= r * r;
}
bool drag_on_sphere(int x, int y) { return in_circle(x, y, SPH_CX, SPH_CY, SPH_R); }

} // namespace

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    if (SDL_Init(SDL_INIT_VIDEO) < 0) { fprintf(stderr, "[orb] SDL_Init: %s\n", SDL_GetError()); return 1; }

    SDL_Window *win = SDL_CreateWindow("my-agent-orb",
        SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, WIN_W, WIN_H,
        SDL_WINDOW_BORDERLESS | SDL_WINDOW_ALWAYS_ON_TOP);
    if (!win) { fprintf(stderr, "[orb] window: %s\n", SDL_GetError()); SDL_Quit(); return 1; }

    // 放到屏幕右上角
    SDL_DisplayMode dm;
    if (SDL_GetCurrentDisplayMode(0, &dm) == 0)
        SDL_SetWindowPosition(win, dm.w - WIN_W - 24, 56);

    SDL_Renderer *ren = SDL_CreateRenderer(win, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!ren) ren = SDL_CreateRenderer(win, -1, SDL_RENDERER_SOFTWARE);
    SDL_Texture *sphere = make_sphere(ren, SPH_R);

    bool run = true;
    while (run) {
        SDL_Event e;
        while (SDL_PollEvent(&e)) {
            if (e.type == SDL_QUIT) run = false;
            else if (e.type == SDL_KEYDOWN && e.key.keysym.sym == SDLK_ESCAPE) run = false;
            else if (e.type == SDL_MOUSEBUTTONDOWN && e.button.button == SDL_BUTTON_LEFT) {
                int mx = e.button.x, my = e.button.y;
                // 关闭 ×
                if (mx >= WIN_W - 26 && my <= 26) { run = false; }
                else if (in_circle(mx, my, CAM_CX, CAM_CY, BTN_R)) {
                    runbg("/opt/my-agent/voice/voice.sh camera");
                } else if (in_circle(mx, my, MUS_CX, MUS_CY, BTN_R)) {
                    runbg("kill $(cat /tmp/myagent_music.pid) 2>/dev/null; /usr/bin/vlc");
                } else if (drag_on_sphere(mx, my)) {
                    g_drag = true; g_moved = false;
                    int wx, wy; SDL_GetWindowPosition(win, &wx, &wy);
                    int gx, gy; SDL_GetGlobalMouseState(&gx, &gy);
                    g_drag_dx = gx - wx; g_drag_dy = gy - wy;
                }
            } else if (e.type == SDL_MOUSEBUTTONUP && e.button.button == SDL_BUTTON_LEFT) {
                if (g_drag && !g_moved) runbg("/opt/my-agent/voice/voice.sh camera"); // 单击球体
                g_drag = false;
            } else if (e.type == SDL_MOUSEMOTION && g_drag) {
                int gx, gy; SDL_GetGlobalMouseState(&gx, &gy);
                SDL_SetWindowPosition(win, gx - g_drag_dx, gy - g_drag_dy);
                g_moved = true;
            }
        }

        // 绘制
        SDL_SetRenderDrawColor(ren, 16, 20, 28, 255);
        SDL_RenderClear(ren);
        // 球体
        SDL_Rect dst = { SPH_CX - SPH_R, SPH_CY - SPH_R, SPH_R * 2, SPH_R * 2 };
        SDL_RenderCopy(ren, sphere, nullptr, &dst);

        // 摄像头按钮
        SDL_SetRenderDrawColor(ren, 46, 58, 78, 255); fill_circle(ren, CAM_CX, CAM_CY, BTN_R);
        SDL_SetRenderDrawColor(ren, 235, 240, 250, 255);
        SDL_Rect body = { CAM_CX - 13, CAM_CY - 8, 26, 17 };
        SDL_RenderFillRect(ren, &body);
        fill_circle(ren, CAM_CX, CAM_CY, 5);
        SDL_SetRenderDrawColor(ren, 46, 58, 78, 255); fill_circle(ren, CAM_CX, CAM_CY, 3);

        // 音乐按钮
        SDL_SetRenderDrawColor(ren, 78, 58, 78, 255); fill_circle(ren, MUS_CX, MUS_CY, BTN_R);
        SDL_SetRenderDrawColor(ren, 245, 235, 250, 255);
        SDL_RenderDrawLine(ren, MUS_CX + 6, MUS_CY - 11, MUS_CX + 6, MUS_CY + 6);
        SDL_RenderDrawLine(ren, MUS_CX + 6, MUS_CY - 11, MUS_CX + 15, MUS_CY - 13);
        SDL_RenderDrawLine(ren, MUS_CX + 15, MUS_CY - 13, MUS_CX + 15, MUS_CY + 4);
        fill_circle(ren, MUS_CX + 1, MUS_CY + 7, 5);
        fill_circle(ren, MUS_CX + 10, MUS_CY + 5, 5);

        // 关闭 ×
        SDL_SetRenderDrawColor(ren, 150, 160, 175, 255);
        SDL_RenderDrawLine(ren, WIN_W - 20, 8, WIN_W - 10, 18);
        SDL_RenderDrawLine(ren, WIN_W - 10, 8, WIN_W - 20, 18);

        SDL_RenderPresent(ren);
        SDL_Delay(16);
    }

    if (sphere) SDL_DestroyTexture(sphere);
    SDL_DestroyRenderer(ren);
    SDL_DestroyWindow(win);
    SDL_Quit();
    return 0;
}
