#!/usr/bin/env bash
#
# 创建一把本机自签名代码签名证书，放进一个独立的钥匙串。
#
# 为什么需要它：
#   ad-hoc 签名（codesign -s -）的 CDHash 每次重新编译都会变化，macOS 会把每次构建
#   都当成一个全新的 App，于是每次都要重新到「系统设置 › 隐私与安全性 › 辅助功能」
#   里重新授权。改用一把固定的证书签名后，代码要求（designated requirement）保持稳定，
#   辅助功能授权一次即可长期有效。
#
# 为什么用独立钥匙串：
#   把私钥放在登录钥匙串里时，codesign 取私钥要靠 SecurityAgent 弹窗授权；在
#   `xcodebuild` 这样的无人值守进程里，弹窗不会被应答，签名会随机失败并报
#   `errSecInternalComponent`。独立钥匙串的密码由我们掌握，因此可以设置
#   key partition list 让 codesign 免弹窗使用私钥，签名从此稳定。
#
# 本脚本做的事情，全部限制在当前用户的钥匙串范围内，不需要管理员权限：
#   1. 创建（或复用）独立钥匙串 ~/Library/Keychains/zWGestures.keychain-db
#   2. 生成一对只用于代码签名的自签名证书与私钥
#   3. 导入并把 key partition list 设为允许 codesign 免弹窗使用
#   4. 把该钥匙串加入用户钥匙串搜索列表
#   5. 用一个临时副本验证签名确实可用
#
# 撤销方法：
#   security delete-keychain ~/Library/Keychains/zWGestures.keychain-db
#   security list-keychains -d user -s ~/Library/Keychains/login.keychain-db
#
set -euo pipefail

CERT_NAME="zWGestures Local Signing"
KEYCHAIN_PATH="${HOME}/Library/Keychains/zWGestures.keychain-db"
KEYCHAIN_PASSWORD="zwgestures"
OPENSSL=/usr/bin/openssl

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
chmod 700 "$WORK"

echo "1/5 准备独立钥匙串…"
if [ -f "$KEYCHAIN_PATH" ]; then
    echo "    已存在：${KEYCHAIN_PATH}"
else
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
    echo "    已创建：${KEYCHAIN_PATH}"
fi
security set-keychain-settings -l -u -t 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

EXISTING_CERT=0
if security find-certificate -c "$CERT_NAME" "$KEYCHAIN_PATH" >/dev/null 2>&1; then
    EXISTING_CERT=1
    echo "2/5 证书已存在，复用"
else
    echo "2/5 生成自签名证书与私钥…"
    "$OPENSSL" req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
        -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
        -subj "/CN=${CERT_NAME}/O=zWGestures/C=CN" \
        -addext "basicConstraints=critical,CA:false" \
        -addext "keyUsage=critical,digitalSignature" \
        -addext "extendedKeyUsage=critical,codeSigning"

    "$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
        -name "$CERT_NAME" -out "$WORK/zwg.p12" -passout pass:zwgestures
fi

echo "3/5 导入并设置 key partition list…"
if [ "$EXISTING_CERT" -eq 0 ]; then
    security import "$WORK/zwg.p12" -k "$KEYCHAIN_PATH" -P zwgestures \
        -T /usr/bin/codesign -T /usr/bin/security -A
fi
# 这一步是关键：没有它，codesign 每次取私钥都要经过 SecurityAgent。
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
    -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null

echo "4/5 加入钥匙串搜索列表…"
CURRENT="$(security list-keychains -d user | sed -e 's/^[[:space:]]*//' -e 's/"//g')"
if printf '%s\n' "$CURRENT" | grep -qxF "$KEYCHAIN_PATH"; then
    echo "    已在搜索列表中"
else
    security list-keychains -d user -s $CURRENT "$KEYCHAIN_PATH"
    echo "    已加入（原列表保留）"
fi

echo "5/5 验证签名…"
printf 'signing probe\n' > "$WORK/probe"
if codesign --force --sign "$CERT_NAME" --keychain "$KEYCHAIN_PATH" \
    --timestamp=none "$WORK/probe" >/dev/null 2>&1; then
    echo "    ✓ 签名可用"
else
    echo "    ✗ 签名失败，需要排查" >&2
    exit 1
fi

echo
echo "证书已就绪：${CERT_NAME}"
echo "钥匙串：${KEYCHAIN_PATH}（密码 ${KEYCHAIN_PASSWORD}）"
echo "注意：这是自签名证书，只用于本机开发签名，不要用于分发。"
