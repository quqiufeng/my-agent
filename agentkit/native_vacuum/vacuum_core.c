// vacuum_core.c — 科沃斯 DEEBOT 云控原生内核（C，无 Python）
// 协议对齐 deebot-client：签名 GET 登录 → authcode → loginByItToken → HTTP POST 命令
// 用法: vacuum_core status|start|stop|pause|resume|dock|find|where
// 账号: 环境变量 ECOVACS_ACCOUNT / ECOVACS_PASSWORD
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <ctype.h>
#include <openssl/md5.h>
#include <curl/curl.h>
#include <cjson/cJSON.h>

#define CLIENT_KEY "1520391301804"
#define CLIENT_SECRET "6c319b2a5cd3e66e39159c2e28f2fce9"
#define AUTH_CLIENT_KEY "1520391491841"
#define AUTH_CLIENT_SECRET "77ef58ce3afbe337da74aa8c5ab963a9"
#define LOGIN_URL "https://gl-cn-api.ecovacs.cn"
#define AUTH_URL "https://gl-cn-openapi.ecovacs.cn"
#define PORTAL_URL "https://portal.ecouser.net"
#define DEVICE_ID "6f5b1e2a8c3d4e6f9a1b2c3d4e5f6a7b"
#define REALM "ecouser.net"
#define UA "Dalvik/2.1.0 (Linux; U; Android 5.1.1; A5010 Build/LMY48Z)"

/* ---------- 基础工具 ---------- */
static char *md5hex(const char *s) {
  unsigned char d[MD5_DIGEST_LENGTH];
  MD5((const unsigned char *)s, strlen(s), d);
  char *out = malloc(MD5_DIGEST_LENGTH * 2 + 1);
  for (int i = 0; i < MD5_DIGEST_LENGTH; i++) sprintf(out + i * 2, "%02x", d[i]);
  out[32] = 0;
  return out;
}
static char *urlencode(const char *s) {
  CURL *c = curl_easy_init();
  char *e = curl_easy_escape(c, s, 0);
  char *r = strdup(e ? e : "");
  curl_free(e); curl_easy_cleanup(c);
  return r;
}
struct Buf { char *p; size_t n; };
static size_t wr(void *d, size_t sz, size_t nm, void *u) {
  struct Buf *b = u; size_t t = sz * nm;
  b->p = realloc(b->p, b->n + t + 1);
  memcpy(b->p + b->n, d, t); b->n += t; b->p[b->n] = 0; return t;
}
static char *http(const char *method, const char *url, const char *body,
                  struct curl_slist *hdr) {
  CURL *c = curl_easy_init();
  struct Buf b = {malloc(1), 0}; b.p[0] = 0;
  curl_easy_setopt(c, CURLOPT_URL, url);
  curl_easy_setopt(c, CURLOPT_WRITEFUNCTION, wr);
  curl_easy_setopt(c, CURLOPT_WRITEDATA, &b);
  curl_easy_setopt(c, CURLOPT_TIMEOUT, 60L);
  curl_easy_setopt(c, CURLOPT_FOLLOWLOCATION, 1L);
  if (hdr) curl_easy_setopt(c, CURLOPT_HTTPHEADER, hdr);
  if (body) {
    curl_easy_setopt(c, CURLOPT_POST, 1L);
    curl_easy_setopt(c, CURLOPT_POSTFIELDS, body);
  }
  CURLcode rc = curl_easy_perform(c);
  curl_easy_cleanup(c);
  if (rc != CURLE_OK) { free(b.p); return NULL; }
  return b.p;
}
/* URL 编码的 query 拼接：KV 以 NULL 结尾 */
static char *build_query(char *out, size_t cap, const char **kv) {
  out[0] = 0; size_t n = 0;
  for (int i = 0; kv[i]; i += 2) {
    char *ek = urlencode(kv[i]), *ev = urlencode(kv[i + 1]);
    n += snprintf(out + n, cap - n, "%s%s=%s", n ? "&" : "", ek, ev);
    free(ek); free(ev);
  }
  return out;
}
/* 签名：sign_data = extra + params；authSign=md5(key + concat(sorted k=v) + secret) */
static void sign_params(char *authSign, char *signTextOut, size_t stcap,
                        const char **extra, int nextra, const char **params,
                        int nparams, const char *key, const char *secret) {
  /* 收集 key/value 到数组并排序 */
  const char *ks[64]; const char *vs[64]; int n = 0;
  for (int i = 0; i < nextra; i += 2) { ks[n] = extra[i]; vs[n] = extra[i + 1]; n++; }
  for (int i = 0; i < nparams; i += 2) { ks[n] = params[i]; vs[n] = params[i + 1]; n++; }
  for (int i = 0; i < n; i++) for (int j = i + 1; j < n; j++)
      if (strcmp(ks[j], ks[i]) < 0) { const char *tk = ks[i]; ks[i] = ks[j]; ks[j] = tk;
                                       const char *tv = vs[i]; vs[i] = vs[j]; vs[j] = tv; }
  char *txt = malloc(1); txt[0] = 0; size_t len = 0;
  len += strlen(key); txt = realloc(txt, len + 1); strcpy(txt, key);
  for (int i = 0; i < n; i++) {
    char seg[1200]; snprintf(seg, sizeof seg, "%s=%s", ks[i], vs[i]);
    txt = realloc(txt, len + strlen(seg) + 1); strcpy(txt + len, seg); len += strlen(seg);
  }
  txt = realloc(txt, len + strlen(secret) + 1); strcpy(txt + len, secret);
  if (signTextOut) snprintf(signTextOut, stcap, "%s", txt);
  char *h = md5hex(txt); strcpy(authSign, h); free(h); free(txt);
}

struct Cred { char uid[128]; char token[2048]; char did[64]; char cls[32]; char res[32]; };

/* 登录 → 填 uid/token */
static int do_login(const char *acct, const char *pwd, struct Cred *cr) {
  char devid[64]; snprintf(devid, sizeof devid, "%s", DEVICE_ID);
  char phash[33]; { char *h = md5hex(pwd); strcpy(phash, h); free(h); }
  char ts_ms[32]; long long now = (long long)time(NULL); snprintf(ts_ms, sizeof ts_ms, "%lld000", now);
  char reqid[33]; { char t[64]; snprintf(t, sizeof t, "%lld.000000", now); char *h = md5hex(t); strcpy(reqid, h); free(h); }

  const char *meta[] = {"lang","EN","appCode","global_e","appVersion","1.6.3",
                        "channel","google_play","deviceType","1","country","cn",
                        "deviceId", devid, NULL};
  const char *lp[] = {"account",acct,"password",phash,"requestId",reqid,
                      "authTimespan",ts_ms,"authTimeZone","GMT-8", NULL};
  char sign[33], st[4096];
  sign_params(sign, st, sizeof st, meta, 14, lp, 10, CLIENT_KEY, CLIENT_SECRET);
  const char *lq[] = {"account",acct,"password",phash,"requestId",reqid,
                      "authTimespan",ts_ms,"authTimeZone","GMT-8",
                      "authSign",sign,"authAppkey",CLIENT_KEY, NULL};
  char q[4096]; build_query(q, sizeof q, lq);
  char url[1024];
  snprintf(url, sizeof url, "%s/v1/private/cn/EN/%s/global_e/1.6.3/google_play/1/user/loginCheckMobile?%s",
           LOGIN_URL, devid, q);
  struct curl_slist *h = curl_slist_append(NULL, "User-Agent: " UA);
  char *r = http("GET", url, NULL, h); curl_slist_free_all(h);
  if (r && getenv("VACUUM_DEBUG")) fprintf(stderr, "[login] %s\n", r);
  if (!r) return -1;
  cJSON *j = cJSON_Parse(r); free(r);
  if (!j) return -2;
  cJSON *code = cJSON_GetObjectItem(j, "code"), *data = cJSON_GetObjectItem(j, "data");
  if (!code || strcmp(code->valuestring, "0000") || !data) { cJSON_Delete(j); return -3; }
  char uid[128], atok[2048];
  cJSON *ji = cJSON_GetObjectItem(data, "uid"); cJSON *at = cJSON_GetObjectItem(data, "accessToken");
  strncpy(uid, ji->valuestring, sizeof uid - 1); strncpy(atok, at->valuestring, sizeof atok - 1);
  cJSON_Delete(j);

  /* authcode */
  const char *extra2[] = {"openId","global", NULL};
  const char *ap[] = {"uid",uid,"accessToken",atok,"bizType","ECOVACS_IOT",
                      "deviceId",devid,"authTimespan",ts_ms, NULL};
  char sign2[33]; char st2[4096];
  sign_params(sign2, st2, sizeof st2, extra2, 2, ap, 10, AUTH_CLIENT_KEY, AUTH_CLIENT_SECRET);
  if (getenv("VACUUM_DEBUG")) fprintf(stderr, "[sign2] %s\n  => %s\n", st2, sign2);
  const char *aq[] = {"uid",uid,"accessToken",atok,"bizType","ECOVACS_IOT",
                      "deviceId",devid,"authTimespan",ts_ms,
                      "authSign",sign2,"authAppkey",AUTH_CLIENT_KEY, NULL};
  char q2[8192]; build_query(q2, sizeof q2, aq);
  char url2[2048]; snprintf(url2, sizeof url2, "%s/v1/global/auth/getAuthCode?%s", AUTH_URL, q2);
  h = curl_slist_append(NULL, "User-Agent: " UA);
  r = http("GET", url2, NULL, h); curl_slist_free_all(h);
  if (r && getenv("VACUUM_DEBUG")) fprintf(stderr, "[authcode] %s\n", r);
  if (!r) return -4;
  j = cJSON_Parse(r); free(r); if (!j) return -5;
  code = cJSON_GetObjectItem(j, "code"); data = cJSON_GetObjectItem(j, "data");
  if (!code || strcmp(code->valuestring, "0000") || !data) { cJSON_Delete(j); return -6; }
  char authcode[2048]; strncpy(authcode, cJSON_GetObjectItem(data, "authCode")->valuestring, sizeof authcode - 1);
  cJSON_Delete(j);

  /* loginByItToken → token */
  char body[4096];
  snprintf(body, sizeof body,
    "{\"edition\":\"ECOGLOBLE\",\"userId\":\"%s\",\"token\":\"%s\",\"realm\":\"%s\","
    "\"resource\":\"%s\",\"org\":\"ECOCN\",\"last\":\"\",\"country\":\"Chinese\",\"todo\":\"loginByItToken\"}",
    uid, authcode, REALM, devid);
  char url3[256]; snprintf(url3, sizeof url3, "%s/api/users/user.do", PORTAL_URL);
  h = curl_slist_append(NULL, "User-Agent: " UA);
  h = curl_slist_append(h, "Content-Type: application/json");
  r = http("POST", url3, body, h); curl_slist_free_all(h);
  if (!r) return -7;
  j = cJSON_Parse(r); free(r); if (!j) return -8;
  cJSON *res = cJSON_GetObjectItem(j, "result");
  if (!res || strcmp(res->valuestring, "ok")) { cJSON_Delete(j); return -9; }
  cJSON *uid2 = cJSON_GetObjectItem(j, "userId"), *tok = cJSON_GetObjectItem(j, "token");
  if (uid2 && uid2->valuestring) strncpy(uid, uid2->valuestring, sizeof uid - 1);
  strncpy(cr->token, tok->valuestring, sizeof cr->token - 1);
  strncpy(cr->uid, uid, sizeof cr->uid - 1);
  cJSON_Delete(j);
  return 0;
}

/* 取设备 did/class/resource（用 auth 头 POST 设备列表） */
static int get_device(struct Cred *cr) {
  char body[8192];
  snprintf(body, sizeof body,
    "{\"userid\":\"%s\",\"todo\":\"GetDeviceList\",\"auth\":{\"with\":\"users\","
    "\"userid\":\"%s\",\"realm\":\"%s\",\"token\":\"%s\",\"resource\":\"%s\"}}",
    cr->uid, cr->uid, REALM, cr->token, DEVICE_ID);
  char url[256]; snprintf(url, sizeof url, "%s/api/users/user.do", PORTAL_URL);
  struct curl_slist *h = curl_slist_append(NULL, "User-Agent: " UA);
  h = curl_slist_append(h, "Content-Type: application/json");
  char *r = http("POST", url, body, h); curl_slist_free_all(h);
  if (!r) return -1;
  cJSON *j = cJSON_Parse(r); free(r); if (!j) return -2;
  cJSON *devs = cJSON_GetObjectItem(j, "devices");
  if (!cJSON_IsArray(devs) || cJSON_GetArraySize(devs) == 0) { cJSON_Delete(j); return -3; }
  cJSON *d = cJSON_GetArrayItem(devs, 0);
  strncpy(cr->did, cJSON_GetObjectItem(d, "did")->valuestring, sizeof cr->did - 1);
  strncpy(cr->cls, cJSON_GetObjectItem(d, "class")->valuestring, sizeof cr->cls - 1);
  strncpy(cr->res, cJSON_GetObjectItem(d, "resource")->valuestring, sizeof cr->res - 1);
  cJSON_Delete(j);
  return 0;
}

/* 发命令：cmdName + payload(JSON 字符串) */
static char *send_cmd(struct Cred *cr, const char *cmdName, const char *payloadJson) {
  char body[8192];
  snprintf(body, sizeof body,
    "{\"cmdName\":\"%s\",\"payload\":%s,\"payloadType\":\"j\",\"td\":\"q\","
    "\"toId\":\"%s\",\"toRes\":\"%s\",\"toType\":\"%s\","
    "\"auth\":{\"with\":\"users\",\"userid\":\"%s\",\"realm\":\"%s\",\"token\":\"%s\",\"resource\":\"%s\"}}",
    cmdName, payloadJson, cr->did, cr->res, cr->cls, cr->uid, REALM, cr->token, DEVICE_ID);
  const char *qp[] = {"mid",cr->cls,"did",cr->did,"td","q","u",cr->uid,
                      "cv","1.67.3","t","a","av","1.3.1", NULL};
  char q[1024]; build_query(q, sizeof q, qp);
  char url[2048]; snprintf(url, sizeof url, "%s/api/iot/devmanager.do?%s", PORTAL_URL, q);
  struct curl_slist *h = curl_slist_append(NULL, "User-Agent: " UA);
  h = curl_slist_append(h, "Content-Type: application/json");
  char *r = http("POST", url, body, h); curl_slist_free_all(h);
  return r;
}

static const char *hdr(void) {
  static char b[256];
  time_t t = time(NULL); struct tm *g = gmtime(&t);
  snprintf(b, sizeof b, "{\"pri\":\"1\",\"ts\":%ld,\"tzm\":480,\"ver\":\"0.0.50\"}", (long)t);
  (void)g; return b;
}

int main(int argc, char **argv) {
  const char *cmd = argc > 1 ? argv[1] : "status";
  const char *acct = getenv("ECOVACS_ACCOUNT"), *pwd = getenv("ECOVACS_PASSWORD");
  if (!acct || !pwd) { fprintf(stderr, "缺 ECOVACS_ACCOUNT/PASSWORD\n"); return 3; }
  curl_global_init(CURL_GLOBAL_DEFAULT);
  struct Cred cr; memset(&cr, 0, sizeof cr);
  int rc = do_login(acct, pwd, &cr);
  if (rc) { fprintf(stderr, "登录失败 rc=%d\n", rc); return 1; }
  rc = get_device(&cr);
  if (rc) { fprintf(stderr, "取设备失败 rc=%d\n", rc); return 1; }

  char payload[512]; char *resp = NULL;
  if (!strcmp(cmd, "status")) {
    snprintf(payload, sizeof payload, "{\"header\":%s}", hdr());
    resp = send_cmd(&cr, "getChargeState", payload);
  } else if (!strcmp(cmd, "start")) {
    snprintf(payload, sizeof payload, "{\"header\":%s,\"body\":{\"data\":{\"act\":\"start\",\"type\":\"auto\"}}}", hdr());
    resp = send_cmd(&cr, "clean", payload);
  } else if (!strcmp(cmd, "stop")) {
    snprintf(payload, sizeof payload, "{\"header\":%s,\"body\":{\"data\":{\"act\":\"stop\"}}}", hdr());
    resp = send_cmd(&cr, "clean", payload);
  } else if (!strcmp(cmd, "pause")) {
    snprintf(payload, sizeof payload, "{\"header\":%s,\"body\":{\"data\":{\"act\":\"pause\"}}}", hdr());
    resp = send_cmd(&cr, "clean", payload);
  } else if (!strcmp(cmd, "resume")) {
    snprintf(payload, sizeof payload, "{\"header\":%s,\"body\":{\"data\":{\"act\":\"resume\"}}}", hdr());
    resp = send_cmd(&cr, "clean", payload);
  } else if (!strcmp(cmd, "dock")) {
    snprintf(payload, sizeof payload, "{\"header\":%s,\"body\":{\"data\":{\"act\":\"go\"}}}", hdr());
    resp = send_cmd(&cr, "charge", payload);
  } else if (!strcmp(cmd, "find")) {
    snprintf(payload, sizeof payload, "{\"header\":%s,\"body\":{\"data\":{\"count\":1,\"sid\":30}}}", hdr());
    resp = send_cmd(&cr, "playSound", payload);
  } else {
    fprintf(stderr, "未知命令: %s\n", cmd); return 2;
  }
  if (!resp) { fprintf(stderr, "命令无响应\n"); return 1; }
  if (getenv("VACUUM_DEBUG")) fprintf(stderr, "%s\n", resp);
  cJSON *jj = cJSON_Parse(resp);
  cJSON *ret = jj ? cJSON_GetObjectItem(jj, "ret") : NULL;
  int ok = ret && ret->valuestring && !strcmp(ret->valuestring, "ok");
  if (!ok) { printf("执行失败: %s\n", resp); free(resp); return 1; }
  if (!strcmp(cmd, "status")) {
    cJSON *b = cJSON_GetObjectItem(cJSON_GetObjectItem(jj, "resp"), "body");
    cJSON *dd = b ? cJSON_GetObjectItem(b, "data") : NULL;
    cJSON *ic = dd ? cJSON_GetObjectItem(dd, "isCharging") : NULL;
    cJSON *md = dd ? cJSON_GetObjectItem(dd, "mode") : NULL;
    int ch = ic && cJSON_IsNumber(ic) ? ic->valueint : 0;
    printf("%s；模式=%s\n", ch == 1 ? "充电中/在充电座" : "空闲/工作中",
           md && md->valuestring ? md->valuestring : "-");
  } else {
    printf("%s\n", !strcmp(cmd, "start") ? "开始清扫" :
                   !strcmp(cmd, "stop") ? "已停止" :
                   !strcmp(cmd, "pause") ? "已暂停" :
                   !strcmp(cmd, "resume") ? "继续清扫" :
                   !strcmp(cmd, "dock") ? "已发送归位（回充）" : "已让它发声（找机）");
  }
  cJSON_Delete(jj);
  free(resp);
  return 0;
}
