#!/usr/bin/env bash
#
# 创建一把本机自签名代码签名证书：zWGestures Local Signing
#
# 为什么需要它：
#   ad-hoc 签名（codesign -s -）的 CDHash 每次重新编译都会变化，macOS 会把每次构建
#   都当成一个全新的 App，于是每次都要重新到「系统设置 › 隐私与安全性 › 辅助功能」
#   里重新授权。改用一把固定的证书签名后，代码要求（designated requirement）保持稳定，
#   辅助功能授权一次即可长期有效。
#
# 本脚本只做三件事，全部限制在当前用户的登录钥匙串内，不需要管理员权限：
#   1. 用 /usr/bin/openssl 生成一对自签名证书 + 私钥（只用于代码签名）
#   2. 打包成 p12 并导入登录钥匙串
#   3. 把该证书加入「用户」信任域并限定为代码签名用途，使 codesign 能识别它
#
# 说明：
#   - 私钥用 -A 导入，即允许本机任意程序免提示使用。这是为了让 xcodebuild 能在无人
#     值守的脚本里反复签名。该证书只能用于本机签名，泄露风险仅限于此。
#   - 第 3 步 macOS 可能弹出钥匙串授权对话框，需要你输入登录密码。
#
# 撤销方法：
#   security delete-identity -c "zWGestures Local Signing"
#   security delete-certificate -c "zWGestures Local Signing" ~/Library/Keychains/login.keychain-db
#
set -euo pipefail

CERT_NAME="zWGestures Local Signing"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"
OPENSSL=/usr/bin/openssl

if security find-certificate -c "$CERT_NAME" >/dev/null 2>&1; then
    echo "已存在同名证书：${CERT_NAME}"
    security find-identity -v -p codesigning | grep -F "$CERT_NAME" || {
        echo "证书已存在但不是可用的签名身份，请先删除后重试：" >&2
        echo "  security delete-identity -c \"${CERT_NAME}\"" >&2
        exit 1
    }
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
chmod 700 "$WORK"

echo "1/3 生成自签名证书与私钥…"
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -subj "/CN=${CERT_NAME}/O=zWGestures/C=CN" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning"

"$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$CERT_NAME" -out "$WORK/zwg.p12" -passout pass:zwgestures

echo "2/3 导入登录钥匙串…"
security import "$WORK/zwg.p12" -k "$KEYCHAIN" -P zwgestures \
    -T /usr/bin/codesign -T /usr/bin/security -A

echo "3/3 加入用户信任域（限定代码签名，可能弹出密码对话框）…"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

echo
if security find-identity -v -p codesigning | grep -F "$CERT_NAME"; then
    echo "✓ 证书已就绪。"
else
    echo "✗ 证书已导入但未被识别为有效的签名身份。" >&2
    echo "  可以尝试在「钥匙串访问」里手动把该证书的信任设置为「始终信任 / 代码签名」。" >&2
    exit 1
fi
