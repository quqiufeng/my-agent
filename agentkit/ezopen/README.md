# agentkit/ezopen — 萤石 EZOPEN 原生 SDK 集成

Linux(统信UOS) 版 EZOPEN SDK + 自编 OpenSSL 1.1.1，用于「对讲/取流」的原生尝试。

## 重新获取（大文件不入库）

```bash
# 1) SDK（官方下载，约 42MB）
curl -sL -o ezopen.tar.gz "https://izhstatic.ys7.com/vasp-openweb/1751461293427_EZUOSOpenSDK_v5.12.0_build20250606.tar.gz"
tar xzf ezopen.tar.gz -C /tmp && cp -r /tmp/EZUOSOpenSDK_*/{inc,lib,demo} agentkit/ezopen/

# 2) 自编 OpenSSL 1.1.1（SDK 需要 libssl.so.1.1）
curl -sL -o openssl11.tar.gz https://github.com/openssl/openssl/releases/download/OpenSSL_1_1_1w/openssl-1.1.1w.tar.gz
tar xzf openssl11.tar.gz && cd openssl-1.1.1w && ./config shared --prefix=$PWD/../agentkit/ezopen/openssl11 && make -j && make install_sw
```

## 构建/运行
```bash
g++ talk.cpp -Iinc -Llib -lOpenNetStream -lcjson -Wl,--allow-shlib-undefined -Wl,-rpath,$PWD/lib -o talk
LD_LIBRARY_PATH="$PWD/openssl11/lib:$PWD/lib" EZVIZ_APPKEY=$EZVIZ_APPKEY EZVIZ_TOK=<token> DEV=802657358 ./talk
```
> 注意：EZUOS SDK 仅 v5.12，**无「视频通话」**；对讲需 EZOpenSDK v5.21+（仅 iOS/Android）。
> `talk` 会话可建，但平台回 `500004`（未授权）。对讲请用手机 App。
