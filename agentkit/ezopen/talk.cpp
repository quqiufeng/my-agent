#include "OpenNetStreamInterFace.h"
#include <cstdio>
#include <cstdlib>
#include <unistd.h>
static void CALLBACK onMsg(const char* s,unsigned i,unsigned e,const char* m,void* u){
  printf("[MSG] type=%u err=%u info=%s\n",i,e,m?m:"");
}
int main(){
  setvbuf(stdout,NULL,_IONBF,0);
  const char* appKey=getenv("EZVIZ_APPKEY"); const char* tok=getenv("EZVIZ_TOK"); const char* ser=getenv("DEV")?:"" ;
  const char* serial = getenv("DEV"); 
  OpenSDK_InitLib("https://openauth.ys7.com","https://open.ys7.com",appKey,false);
  OpenSDK_SetAccessToken(tok);
  OpenSDK_SetMessageCallback(onMsg);
  char* sid=nullptr; int len=0; OpenSDK_AllocSessionEx(onMsg,nullptr,&sid,&len);
  printf("sid=%.*s\n", len, sid?sid:"");
  printf("start=%d\n", OpenSDK_StartVoiceTalkNew(sid,serial,1,""));
  printf("capture=%d\n", OpenSDK_SetVoiceTalkCapture(sid,1));
  printf("play=%d\n", OpenSDK_SetVoiceTalkPlay(sid,1));
  printf(">>> 对讲中(10s)... 说话试试\n");
  sleep(10);
  OpenSDK_SetVoiceTalkCapture(sid,0);
  OpenSDK_SetVoiceTalkPlay(sid,0);
  printf("done\n");
  return 0;
}
