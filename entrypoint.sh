#! /bin/bash
set -ex
if [[ -z "${VER}" ]]; then
  VER="latest"
fi
echo ${VER}

if [[ -z "${UUID}" ]]; then
  UUID="ffc17112-b755-499d-be9f-91a828bd3197"
fi
echo ${UUID}

if [[ -z "${AlterID}" ]]; then
  AlterID="64"
fi
echo ${AlterID}

if [[ -z "${V2_Path}" ]]; then
  V2_Path="/static"
fi
echo ${V2_Path}

if [[ -z "${V2_QR_Path}" ]]; then
  V2_QR_Path="qr_img"
fi
echo ${V2_QR_Path}

rm -rf /etc/localtime
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
date -R


if [ "$VER" = "latest" ]; then
  V2RAY_URL="https://github.com/v2fly/v2ray-core/releases/latest/download/v2ray-linux-64.zip"
else
  V_VER="v$VER"
  V2RAY_URL="https://github.com/v2fly/v2ray-core/releases/download/$V_VER/v2ray-linux-64.zip"
fi

mkdir /v2raybin
cd /v2raybin
echo ${V2RAY_URL}
wget --no-check-certificate -qO 'v2ray.zip' ${V2RAY_URL}
unzip v2ray.zip
rm -rf v2ray.zip

#C_VER="v1.0.3"
C_VER="2.2.1"
mkdir /caddybin
cd /caddybin
CADDY_URL="https://github.com/caddyserver/caddy/releases/download/v$C_VER/caddy_${C_VER}_linux_amd64.tar.gz"
echo ${CADDY_URL}
wget --no-check-certificate -qO 'caddy.tar.gz' ${CADDY_URL}
tar xvf caddy.tar.gz
rm -rf caddy.tar.gz
chmod +x caddy

cd /wwwroot
tar xvf wwwroot.tar.gz
rm -rf wwwroot.tar.gz

F_VER="0.34.3"
mkdir /frp
cd /frp
FRP_URL="https://github.com/fatedier/frp/releases/download/v$F_VER/frp_${F_VER}_linux_amd64.tar.gz"
echo ${FRP_URL}
wget --no-check-certificate -qO 'frp.tar.gz' ${FRP_URL}
tar xvf frp.tar.gz
rm -rf frp.tar.gz
mv ./frp_${F_VER}_linux_amd64/frps /frp/
rm -rf frp_${F_VER}_linux_amd64
chmod +x frps


cat <<-EOF > /v2raybin/config.json
{
    "log":{
        "loglevel":"warning"
    },
    "reverse":{
      "portals":[  
        {  
          "tag":"portal",
          "domain":"private.cloud.com"
        }
      ]
    },
    "inbounds": [
      {
        "protocol": "dokodemo-door",
        "port": 3333,
        "settings": {
          "address":"",
          "network": "tcp,udp",
          "followRedirect": false
        },
        "sniffing": {
          "enabled": true,
          "destOverride": ["http", "tls"]
        },
        "tag":"external"
      },{
        "tag": "tunnel",
        "protocol":"vmess",
        "listen":"127.0.0.1",
        "port":2333,
        "settings":{
            "clients":[
                {
                    "id":"${UUID}",
                    "level":1,
                    "alterId":${AlterID}
                }
            ]
        },
        "streamSettings":{
            "network":"ws",
            "wsSettings":{
                "path":"${V2_Path}"
            }
        }
    }],
    "outbounds":[{
        "protocol":"freedom",
        "settings":{
        }
    }],
    "routing": {
      "rules": [
        {
          "type": "field",
          "inboundTag": ["external"],
          "outboundTag": "portal"
        },{
            "type": "field",
            "inboundTag": ["tunnel"],
            "domain": ["full:private.cloud.com"],
            "outboundTag": "portal"
        }]
    }
}
EOF

echo /v2raybin/config.json
cat /v2raybin/config.json


cat <<-EOF > /caddybin/Caddyfile
:${PORT}
{
  root * /wwwroot
  file_server
  reverse_proxy /${V2_Path} 127.0.0.1:2333
  @frp {
    {header.frp}.startsWith("6")
  }
  reverse_proxy @frp 127.0.0.1:{header.frp}
  @door {
    header url *_eshion
    header_regexp url url (.*)_eshion
  }
  reverse_proxy @door 127.0.0.1:3333 {
    header_up Host {http.regexp.url.0}
  }
}
EOF

echo /caddybin/Caddyfile
cat /caddybin/Caddyfile

cat <<-EOF > /frp/frps.ini
[common]
bind_port = 6000
vhost_http_port = 6080
vhost_https_port = 6443
EOF

echo /frp/frps.ini
cat /frp/frps.ini

cat <<-EOF > /v2raybin/vmess.json
{
    "v": "2",
    "ps": "${AppName}.herokuapp.com",
    "add": "${AppName}.herokuapp.com",
    "port": "443",
    "id": "${UUID}",
    "aid": "${AlterID}",
    "net": "ws",
    "type": "none",
    "host": "",
    "path": "${V2_Path}",
    "tls": "tls"
}
EOF

if [ "$AppName" = "no" ]; then
  echo "不生成二维码"
else
  mkdir /wwwroot/${V2_QR_Path}
  vmess="vmess://$(cat /v2raybin/vmess.json | base64 -w 0)"
  Linkbase64=$(echo -n "${vmess}" | tr -d '\n' | base64 -w 0)
  echo "${Linkbase64}" | tr -d '\n' > /wwwroot/${V2_QR_Path}/index.html
  echo -n "${vmess}" | qrencode -s 6 -o /wwwroot/${V2_QR_Path}/v2.png
fi

cd /frp
./frps run -c /frp/frps.ini &
cd /v2raybin
./v2ray -config config.json &
cd /caddybin
./caddy run --config /caddybin/Caddyfile
