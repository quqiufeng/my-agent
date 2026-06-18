#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <time.h>
#include <stdarg.h>
#include <sys/stat.h>
#include <signal.h>

#define INTERVAL 300          // 5 分钟
#define LOG_FILE "/tmp/wechat_monitor.log"
#define TMP_DIR "/tmp/wechat_monitor"
#define SHELL_CMD_MAX 512

// 日志写入
static void log_msg(const char *fmt, ...) {
    char buf[256];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);

    time_t t = time(NULL);
    struct tm *tm = localtime(&t);
    char ts[32];
    strftime(ts, sizeof(ts), "%H:%M:%S", tm);

    FILE *f = fopen(LOG_FILE, "a");
    if (f) {
        fprintf(f, "[%s] %s\n", ts, buf);
        fclose(f);
    }
    printf("[%s] %s\n", ts, buf);
    fflush(stdout);
}

// 执行 shell 命令
static int run_cmd(const char *fmt, ...) {
    char cmd[SHELL_CMD_MAX];
    va_list args;
    va_start(args, fmt);
    vsnprintf(cmd, sizeof(cmd), fmt, args);
    va_end(args);
    return system(cmd);
}

// 检测未读红点，返回红点数（-1 表示失败）
static int check_unread() {
    // 1. 激活微信
    run_cmd("xdotool search --name 微信 windowactivate 2>/dev/null");
    usleep(500000);

    // 2. 获取窗口位置
    char geo_file[128];
    snprintf(geo_file, sizeof(geo_file), "%s/geo.txt", TMP_DIR);
    run_cmd("xdotool getactivewindow getwindowgeometry > %s 2>/dev/null", geo_file);

    FILE *f = fopen(geo_file, "r");
    if (!f) return -1;
    char line[256];
    int wx = 0, wy = 0, ww = 0, wh = 0;
    while (fgets(line, sizeof(line), f)) {
        if (sscanf(line, " Position: %d,%d", &wx, &wy) == 2) continue;
        if (sscanf(line, " Geometry: %dx%d", &ww, &wh) == 2) continue;
    }
    fclose(f);
    if (ww == 0 || wh == 0) return -1;

    // 3. 截图
    char shot[128];
    snprintf(shot, sizeof(shot), "%s/wechat.png", TMP_DIR);
    run_cmd("import -window root -crop %dx%d+%d+%d '%s' 2>/dev/null", ww, wh, wx, wy, shot);

    // 4. 生成红色掩码
    run_cmd("convert '%s' +repage -fx '(r>g*2.2&&r>b*2.2&&r>0.7&&g<0.5)?1:0' '%s/_red.png' 2>/dev/null", shot, TMP_DIR);

    // 5. 连通分量分析
    char cc_file[128];
    snprintf(cc_file, sizeof(cc_file), "%s/cc.txt", TMP_DIR);
    run_cmd("convert '%s/_red.png' -define connected-components:verbose=true -connected-components 4 /dev/null 2>/dev/null | grep -v '0:\\|bgcolor\\|id:' > '%s'", TMP_DIR, cc_file);

    // 6. 统计符合条件的红点
    f = fopen(cc_file, "r");
    if (!f) return 0;

    int count = 0;
    while (fgets(line, sizeof(line), f)) {
        int id, w, h, x, y, px;
        if (sscanf(line, "%d: %dx%d+%d+%d %*f,%*f %d", &id, &w, &h, &x, &y, &px) >= 5) {
            // 过滤：大小 5~20px，左侧（x < 窗口宽*0.4），有效像素 >= 20
            if (w >= 5 && h >= 5 && w <= 20 && h <= 20 && x < ww * 0.4 && px >= 20) {
                count++;
            }
        }
    }
    fclose(f);
    return count;
}

// 信号处理
static volatile int keep_running = 1;
static void handle_signal(int sig) {
    keep_running = 0;
}

int main(int argc, char *argv[]) {
    int once = (argc > 1 && strcmp(argv[1], "--once") == 0);

    // 创建临时目录
    mkdir(TMP_DIR, 0755);

    // 守护进程模式
    if (!once) {
        pid_t pid = fork();
        if (pid < 0) { perror("fork"); return 1; }
        if (pid > 0) {
            printf("[微信监控] 守护进程已启动 (PID: %d)\n", pid);
            printf("日志: %s\n", LOG_FILE);
            return 0;  // 父进程退出
        }
        // 子进程：新会话
        setsid();
        chdir("/");
        // 关闭标准 I/O
        fclose(stdin); fclose(stdout); fclose(stderr);
        // 打开日志作为 stdout/stderr
        freopen(LOG_FILE, "a", stdout);
        freopen(LOG_FILE, "a", stderr);
        setvbuf(stdout, NULL, _IONBF, 0);
    }

    // 信号处理
    signal(SIGINT, handle_signal);
    signal(SIGTERM, handle_signal);

    log_msg("微信监控启动%s", once ? "（单次模式）" : "（每5分钟检测）");

    int prev_count = 0;
    while (keep_running) {
        int count = check_unread();
        if (count >= 0) {
            if (count > 0) {
                log_msg("[%d 条未读]", count);
                if (count != prev_count) {
                    prev_count = count;
                    log_msg("!! 有新消息 !!");
                }
            } else {
                log_msg("[无新消息]");
                prev_count = 0;
            }
        } else {
            log_msg("[错误] 检测失败");
        }
        if (once) break;

        // 等待 INTERVAL 秒（每 5 秒检查一次信号）
        for (int i = 0; i < INTERVAL && keep_running; i++) {
            sleep(1);
        }
    }

    log_msg("监控停止");
    return 0;
}
