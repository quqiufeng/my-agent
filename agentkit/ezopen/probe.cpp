#include "OpenNetStreamInterFace.h"
#include <cstdio>
#include <cstdlib>
#include <unistd.h>
static void CALLBACK onMsg(const char* s,unsigned i,unsigned e,const char* m,void* u){}
int main(){
  setvbuf(stdout,NULL,_IONBF,0);
  const char* appKey=getenv("EZVIZ_APPKEY"); const char* tok=getenv("EZVIZ_TOK");
  OpenSDK_InitLib("https://openauth.ys7.com","https://open.ys7.com",appKey,false);
  OpenSDK_SetAccessToken(tok);
  char* sid=nullptr; int len=0; OpenSDK_AllocSessionEx(onMsg,nullptr,&sid,&len);
  printf("sid=%.*s\n", len, sid?sid:"");
  int r=OpenSDK_StartVoiceTalkNew(sid,"802657358",1,"");
  printf("StartVoiceTalkNew(empty)=%d lastErr=%d\n", r, OpenSDK_GetLastErrorCode());
  printf("  desc=%s\n", OpenSDK_GetLastErrorDesc());
  r=OpenSDK_StartVoiceTalkNew(sid,"802657358",1,tok);
  printf("StartVoiceTalkNew(accessTok)=%d lastErr=%d\n", r, OpenSDK_GetLastErrorCode());
  printf("  desc=%s\n", OpenSDK_GetLastErrorDesc());
  sleep(2);
  printf("done\n");
  return 0;
}
