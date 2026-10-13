/* kindle-ui — LVGL(C) + LuaJIT + agent 控制通道
 * 显示：LVGL 渲染到内存灰度缓冲(1200x824)，节流后写出 BMP 并调用
 *       /usr/sbin/eips -f -g 刷新（eips 是系统自带、已验证稳的 e-ink 刷新路径）。
 *       —— 不直接写 /dev/fb0、不写 /proc/eink_fb/update_display（那条路会刷花屏）。
 * 输入：五向键 /dev/input/event1 (回退 event0) → LVGL keypad。
 * 脚本：启动跑 /mnt/us/ui/init.lua；agent 向 FIFO /tmp/ui.cmd 逐行写 Lua；事件写 /mnt/us/ui/events。
 * Lua API: ui.clear/title/label/text/set/pos/size/align/color/log/button + ui.ALIGN_*
 */
#include "lvgl.h"
#include "extra/libs/freetype/lv_freetype.h"
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdarg.h>
#include <fcntl.h>
#include <unistd.h>
#include <time.h>
#include <sys/stat.h>
#include <linux/input.h>

#define DISP_W 824
#define DISP_H 1200
#define CMD_FIFO "/tmp/ui.cmd"
#define EVT_FILE "/mnt/us/ui/events"
#define INIT_LUA "/mnt/us/ui/init.lua"
#define FRAME_PNG "/tmp/ui_frame.png"
#define EIPS_BIN "/usr/sbin/eips"
#define REFRESH_MS 1500

static unsigned char g_gray[DISP_W * DISP_H];
static volatile int g_dirty = 0;
static volatile int g_key = 0;
static volatile int g_ui_dirty = 1;
static long g_last_ms = 0;
static int key_fd = -1;
static int key_fd0 = -1;
static lua_State *L = NULL;
static FILE *evf = NULL;
static lv_group_t *grp = NULL;
static lv_obj_t *g_title = NULL;
static lv_font_t *g_font=NULL, *g_font_big=NULL;

static void emit(const char *fmt, ...){ if(!evf) return; va_list ap; va_start(ap,fmt); vfprintf(evf,fmt,ap); va_end(ap); fputc('\n',evf); fflush(evf); }

/* ---- 显示：LVGL → 灰度缓冲 ---- */
static void flush_cb(lv_disp_drv_t *drv, const lv_area_t *area, lv_color_t *cp){
    for(int v=area->y1; v<=area->y2; v++)
        for(int u=area->x1; u<=area->x2; u++){
            lv_color_t c = *cp++;
            uint32_t r=c.ch.red<<3, g=c.ch.green<<2, b=c.ch.blue<<3;
            g_gray[v*DISP_W + u] = (unsigned char)((r*2126 + g*7152 + b*722)/10000);
        }
    g_dirty = 1;
    lv_disp_flush_ready(drv);
}

static const unsigned char PNG_SIG[8]={0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a};
static uint32_t crct[256];
static void crc_setup(void){ for(uint32_t n=0;n<256;n++){uint32_t c=n; for(int k=0;k<8;k++) c=(c&1)?(0xedb88320u^(c>>1)):(c>>1); crct[n]=c;} }
static uint32_t crc_upd(uint32_t crc,const unsigned char*b,int len){ for(int i=0;i<len;i++) crc=crct[(crc^b[i])&0xff]^(crc>>8); return crc; }
static void be32(unsigned char*o,uint32_t v){ o[0]=v>>24;o[1]=v>>16;o[2]=v>>8;o[3]=v; }
static void chunk(FILE*f,const char*type,const unsigned char*data,int len){
    unsigned char lb[4]; be32(lb,(uint32_t)len); fwrite(lb,1,4,f);
    fwrite(type,1,4,f); if(len) fwrite(data,1,len,f);
    uint32_t c=0xffffffff; c=crc_upd(c,(const unsigned char*)type,4); if(len) c=crc_upd(c,data,len); c^=0xffffffff;
    unsigned char cb[4]; be32(cb,c); fwrite(cb,1,4,f);
}
static int write_png(const char*path){
    static int inited=0; if(!inited){ crc_setup(); inited=1; }
    const int W=DISP_W,H=DISP_H;
    FILE*f=fopen(path,"wb"); if(!f) return -1;
    fwrite(PNG_SIG,1,8,f);
    unsigned char ihdr[13]; be32(ihdr,W); be32(ihdr+4,H); ihdr[8]=8; ihdr[9]=0; ihdr[10]=0; ihdr[11]=0; ihdr[12]=0;
    chunk(f,"IHDR",ihdr,13);
    long rawlen=(long)H*(W+1);
    unsigned char *raw=malloc(rawlen);
    if(!raw){ fclose(f); return -1; }
    for(int y=0;y<H;y++){ raw[(long)y*(W+1)]=0; memcpy(raw+(long)y*(W+1)+1, g_gray+(size_t)y*W, W); }
    long cap=rawlen + (rawlen/65535+1)*5 + 16;
    unsigned char *z=malloc(cap); if(!z){ free(raw); fclose(f); return -1; }
    long zl=0; z[zl++]=0x78; z[zl++]=0x01;
    long off=0;
    while(off<rawlen){ long blk=rawlen-off; if(blk>65535)blk=65535; int last=(off+blk>=rawlen);
        z[zl++]=last?1:0; z[zl++]=blk&0xff; z[zl++]=(blk>>8)&0xff; unsigned nlen=(unsigned)((~blk)&0xffff); z[zl++]=nlen&0xff; z[zl++]=(nlen>>8)&0xff;
        memcpy(z+zl,raw+off,blk); zl+=blk; off+=blk;
    }
    uint32_t a=1,b=0; for(long i=0;i<rawlen;i++){ a=(a+raw[i])%65521; b=(b+a)%65521; }
    uint32_t ad=(b<<16)|a; z[zl++]=ad>>24; z[zl++]=ad>>16; z[zl++]=ad>>8; z[zl++]=ad;
    chunk(f,"IDAT",z,zl);
    chunk(f,"IEND",NULL,0);
    free(raw); free(z); fclose(f); return 0;
}
static void do_refresh(void){
    if(write_png(FRAME_PNG)==0){
        char cmd[128]; snprintf(cmd,sizeof cmd, EIPS_BIN " -f -g " FRAME_PNG " >/dev/null 2>&1");
        if(system(cmd)!=0){ }
    }
}

/* ---- 输入 ---- */
static void key_read(lv_indev_drv_t *drv, lv_indev_data_t *data){
    (void)drv; struct input_event ev; static lv_key_t last=0; static int pr=0;
    if(key_fd0>=0) while(read(key_fd0,&ev,sizeof ev)==(ssize_t)sizeof ev){
        if(ev.type!=EV_KEY||ev.value!=1) continue;
        if(ev.code==KEY_HOME) g_key=1000; else if(ev.code==KEY_BACK) g_key=1001; else if(ev.code==KEY_MENU) g_key=1002; else if(ev.code==KEY_LEFT) g_key=(int)LV_KEY_LEFT; else if(ev.code==KEY_RIGHT) g_key=(int)LV_KEY_RIGHT;
    }
    if(key_fd>=0) while(read(key_fd,&ev,sizeof ev)==(ssize_t)sizeof ev){
        if(ev.type!=EV_KEY) continue; lv_key_t k=0;
        switch(ev.code){
            case KEY_UP:k=LV_KEY_UP;break; case KEY_DOWN:k=LV_KEY_DOWN;break;
            case KEY_LEFT:k=LV_KEY_LEFT;break; case KEY_RIGHT:k=LV_KEY_RIGHT;break;
            case KEY_ENTER:k=LV_KEY_ENTER;break; default:k=0;
        }
        if(!k) continue; if(ev.value==1){last=k;pr=1;g_key=(int)k;} else if(ev.value==0) pr=0;
    }
    data->key=last; data->state=pr?LV_INDEV_STATE_PRESSED:LV_INDEV_STATE_RELEASED;
}

/* ---- Lua <-> LVGL ---- */
static lv_obj_t* new_label(lv_obj_t*par,const char*t,int sz){
    lv_obj_t*o=lv_label_create(par); lv_label_set_text(o,t?t:"");
    lv_obj_set_style_text_color(o,lv_color_black(),0);
    lv_obj_set_style_text_font(o, (sz>=32&&g_font_big)?g_font_big:(g_font?g_font:&lv_font_montserrat_14), 0);
    return o;
}
static int l_clear(lua_State*S){ lv_obj_clean(lv_scr_act()); g_title=NULL; if(grp) lv_group_del(grp); grp=lv_group_create(); return 0; }
static int l_title(lua_State*S){ const char*t=luaL_checkstring(S,1); if(!g_title){ g_title=new_label(lv_scr_act(),t,32); lv_obj_align(g_title,LV_ALIGN_TOP_MID,0,24);} else lv_label_set_text(g_title,t); lua_pushlightuserdata(S,g_title); return 1; }
static int l_label(lua_State*S){ int sz=luaL_optinteger(S,2,24); lv_obj_t*o=new_label(lv_scr_act(),luaL_checkstring(S,1),sz); lua_pushlightuserdata(S,o); return 1; }
static int l_text(lua_State*S){ int x=luaL_checkinteger(S,1),y=luaL_checkinteger(S,2); const char*t=luaL_checkstring(S,3); int sz=luaL_optinteger(S,4,24); lv_obj_t*o=new_label(lv_scr_act(),t,sz); lv_obj_set_pos(o,x,y); lua_pushlightuserdata(S,o); return 1; }
static int l_set(lua_State*S){ lv_obj_t*o=lua_touserdata(S,1); const char*t=luaL_checkstring(S,2); if(o) lv_label_set_text(o,t); return 0; }
static int l_pos(lua_State*S){ lv_obj_t*o=lua_touserdata(S,1); if(o) lv_obj_set_pos(o,(int)luaL_checkinteger(S,2),(int)luaL_checkinteger(S,3)); return 0; }
static int l_size(lua_State*S){ lv_obj_t*o=lua_touserdata(S,1); if(o) lv_obj_set_size(o,(int)luaL_checkinteger(S,2),(int)luaL_checkinteger(S,3)); return 0; }
static int l_align(lua_State*S){ lv_obj_t*o=lua_touserdata(S,1); lv_align_t a=(lv_align_t)luaL_checkinteger(S,2); if(o) lv_obj_align(o,a,(int)luaL_optinteger(S,3,0),(int)luaL_optinteger(S,4,0)); return 0; }
static int l_color(lua_State*S){ lv_obj_t*o=lua_touserdata(S,1); unsigned hex=(unsigned)luaL_checkinteger(S,2); if(o) lv_obj_set_style_text_color(o,lv_color_hex(hex),0); return 0; }
static int l_show(lua_State*S){ lv_obj_t*o=lua_touserdata(S,1); int v=lua_toboolean(S,2); if(o){ if(v) lv_obj_clear_flag(o,LV_OBJ_FLAG_HIDDEN); else lv_obj_add_flag(o,LV_OBJ_FLAG_HIDDEN);} return 0; }
static int l_hr(lua_State*S){ int x=luaL_checkinteger(S,1),y=luaL_checkinteger(S,2),w=luaL_checkinteger(S,3); lv_obj_t*o=lv_obj_create(lv_scr_act()); lv_obj_set_size(o,w,1); lv_obj_set_pos(o,x,y); lv_obj_set_style_bg_color(o,lv_color_hex(0xbbbbbb),0); lv_obj_set_style_bg_opa(o,LV_OPA_COVER,0); lv_obj_set_style_border_width(o,0,0); lv_obj_set_style_radius(o,0,0); lv_obj_clear_flag(o,LV_OBJ_FLAG_SCROLLABLE); lua_pushlightuserdata(S,o); return 1; }
static int l_style(lua_State*S){ lv_obj_t*o=lua_touserdata(S,1); int ls=luaL_optinteger(S,2,0), ts=luaL_optinteger(S,3,0); if(o){ lv_obj_set_style_text_line_space(o,ls,0); lv_obj_set_style_text_letter_space(o,ts,0);} return 0; }
static int l_log(lua_State*S){ emit("log %s",luaL_checkstring(S,1)); return 0; }

static void btn_cb(lv_event_t*e){
    lv_obj_t*btn=lv_event_get_target(e);
    int ref=(int)(intptr_t)lv_obj_get_user_data(btn);
    const char*txt="?"; lv_obj_t*lb=lv_obj_get_child(btn,0); if(lb) txt=lv_label_get_text(lb);
    emit("click %s",txt);
    if(ref && L){ lua_rawgeti(L,LUA_REGISTRYINDEX,ref); if(lua_pcall(L,0,0,0)){ emit("luaerr %s",lua_tostring(L,-1)); lua_pop(L,1);} }
}
static int l_button(lua_State*S){
    const char*t=luaL_checkstring(S,1);
    lv_obj_t*btn=lv_btn_create(lv_scr_act()); lv_obj_set_size(btn,360,110);
    lv_obj_t*lb=new_label(btn,t,32); lv_obj_center(lb);
    if(lua_isfunction(S,2)){ lua_pushvalue(S,2); int ref=luaL_ref(S,LUA_REGISTRYINDEX); lv_obj_set_user_data(btn,(void*)(intptr_t)ref); }
    lv_obj_add_event_cb(btn,btn_cb,LV_EVENT_CLICKED,NULL);
    if(grp) lv_group_add_obj(grp,btn);
    lua_pushlightuserdata(S,btn); return 1;
}
static void list_btn_cb(lv_event_t*e){
    lv_obj_t*btn=lv_event_get_target(e);
    int ref=(int)(intptr_t)lv_obj_get_user_data(btn);
    const char*txt="?"; lv_obj_t*lb=lv_obj_get_child(btn,0); if(lb&&lv_obj_get_child(lb,0)) txt=lv_label_get_text(lv_obj_get_child(lb,0));
    else if(lb) txt=lv_label_get_text(lb);
    emit("open %s",txt);
    if(ref && L){ lua_rawgeti(L,LUA_REGISTRYINDEX,ref); lua_pushstring(L,txt); if(lua_pcall(L,1,0,0)){ emit("luaerr %s",lua_tostring(L,-1)); lua_pop(L,1);} }
}
static int l_list(lua_State*S){
    lv_obj_t*lv=lv_list_create(lv_scr_act());
    lv_obj_set_size(lv,DISP_W-100,DISP_H-150);
    lv_obj_align(lv,LV_ALIGN_BOTTOM_MID,0,-12);
    int hascb=lua_isfunction(S,2); int ref=0;
    if(hascb){ lua_pushvalue(S,2); ref=luaL_ref(S,LUA_REGISTRYINDEX); }
    int n=lua_objlen(S,1);
    for(int i=1;i<=n;i++){
        lua_rawgeti(S,1,i); const char*txt=luaL_checkstring(S,-1);
        lv_obj_t*btn=lv_list_add_btn(lv,NULL,txt);
        lv_obj_set_style_text_font(btn, g_font?g_font:&lv_font_montserrat_24, 0);
        lv_obj_set_style_text_color(btn,lv_color_black(),0);
        if(grp) lv_group_add_obj(grp,btn);
        if(hascb) lv_obj_set_user_data(btn,(void*)(intptr_t)ref);
        lv_obj_add_event_cb(btn,list_btn_cb,LV_EVENT_CLICKED,NULL);
        lua_pop(S,1);
    }
    lua_pushlightuserdata(S,lv); return 1;
}

static const luaL_Reg uilib[]={
    {"clear",l_clear},{"title",l_title},{"label",l_label},{"text",l_text},
    {"set",l_set},{"pos",l_pos},{"size",l_size},{"align",l_align},
    {"log",l_log},{"button",l_button},{"color",l_color},{"list",l_list},{"style",l_style},{"hr",l_hr},{"show",l_show},{NULL,NULL}
};
static void dolua(const char*code){ if(luaL_loadstring(L,code)||lua_pcall(L,0,0,0)){ emit("luaerr %s",lua_tostring(L,-1)); lua_pop(L,1); } g_ui_dirty=1; }

int main(void){
    key_fd=open("/dev/input/event1",O_RDONLY|O_NONBLOCK); if(key_fd<0) key_fd=open("/dev/input/event0",O_RDONLY|O_NONBLOCK);
    key_fd0=open("/dev/input/event0",O_RDONLY|O_NONBLOCK);
    mkdir("/mnt/us/ui",0755);
    evf=fopen(EVT_FILE,"a");
    memset(g_gray,255,sizeof g_gray);

    lv_init();
    lv_freetype_init(1,1,0);
    { lv_ft_info_t fi; memset(&fi,0,sizeof fi);
      fi.name="/mnt/us/ui/font.ttf"; fi.weight=26; fi.style=FT_FONT_STYLE_NORMAL;
      if(lv_ft_font_init(&fi)) g_font=fi.font; else emit("nofont");
      lv_ft_info_t fb; memset(&fb,0,sizeof fb);
      fb.name="/mnt/us/ui/font.ttf"; fb.weight=38; fb.style=FT_FONT_STYLE_NORMAL;
      if(lv_ft_font_init(&fb)) g_font_big=fb.font; }
    static lv_color_t buf[DISP_W*40]; static lv_disp_draw_buf_t db; lv_disp_draw_buf_init(&db,buf,NULL,DISP_W*40);
    static lv_disp_drv_t dd; lv_disp_drv_init(&dd); dd.hor_res=DISP_W; dd.ver_res=DISP_H; dd.flush_cb=flush_cb; dd.draw_buf=&db; lv_disp_drv_register(&dd);
    static lv_indev_drv_t id; lv_indev_drv_init(&id); id.type=LV_INDEV_TYPE_KEYPAD; id.read_cb=key_read; lv_indev_t*ind=lv_indev_drv_register(&id);
    grp=lv_group_create(); lv_indev_set_group(ind,grp);
    lv_obj_t*scr=lv_scr_act(); lv_obj_set_style_bg_color(scr,lv_color_white(),0); lv_obj_set_style_bg_opa(scr,LV_OPA_COVER,0);

    L=luaL_newstate(); luaL_openlibs(L);
    luaL_newlib(L,uilib);
    lua_pushinteger(L,LV_ALIGN_CENTER);    lua_setfield(L,-2,"ALIGN_CENTER");
    lua_pushinteger(L,LV_ALIGN_TOP_MID);   lua_setfield(L,-2,"ALIGN_TOP_MID");
    lua_pushinteger(L,LV_ALIGN_BOTTOM_MID);lua_setfield(L,-2,"ALIGN_BOTTOM_MID");
    lua_pushinteger(L,LV_ALIGN_LEFT_MID);  lua_setfield(L,-2,"ALIGN_LEFT_MID");
    lua_pushinteger(L,LV_ALIGN_RIGHT_MID); lua_setfield(L,-2,"ALIGN_RIGHT_MID");
    lua_setglobal(L,"ui");

    if(access(INIT_LUA,R_OK)==0) dolua("dofile('" INIT_LUA "')");
    emit("boot ready");

    mkfifo(CMD_FIFO,0666);
    int cfd=open(CMD_FIFO,O_RDWR|O_NONBLOCK);
    char rbuf[8192]; int rn=0;

    while(1){
        if(cfd>=0){ ssize_t n=read(cfd,rbuf+rn,sizeof(rbuf)-1-rn);
            if(n>0){ rn+=(int)n; rbuf[rn]=0; char*start=rbuf,*nl;
                while((nl=strchr(start,'\n'))){ *nl=0; if(*start) dolua(start); start=nl+1; }
                int rem=(int)strlen(start); memmove(rbuf,start,rem+1); rn=rem;
            } }
        if(g_ui_dirty){ lv_obj_invalidate(lv_scr_act()); lv_refr_now(NULL); g_ui_dirty=0; }
        lv_timer_handler();
        if(g_key){ int kk=g_key; g_key=0;
            const char*nm = kk==1000?"home":kk==1001?"back":kk==1002?"menu":kk==LV_KEY_UP?"up":kk==LV_KEY_DOWN?"down":kk==LV_KEY_LEFT?"left":kk==LV_KEY_RIGHT?"right":kk==LV_KEY_ENTER?"enter":"?";
            lua_getglobal(L,"on_key");
            if(lua_isfunction(L,-1)){ lua_pushstring(L,nm); if(lua_pcall(L,1,0,0)){ emit("luaerr %s",lua_tostring(L,-1)); lua_pop(L,1);} }
            else lua_pop(L,1);
            g_ui_dirty=1;
        }
        struct timespec ts; clock_gettime(CLOCK_MONOTONIC,&ts);
        long now=ts.tv_sec*1000L+ts.tv_nsec/1000000L;
        if((now-g_last_ms)>=REFRESH_MS){ do_refresh(); g_dirty=0; g_last_ms=now; }
        usleep(5000);
    }
    return 0;
}
