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

C_VER="v1.0.3"
mkdir /caddybin
cd /caddybin
CADDY_URL="https://github.com/caddyserver/caddy/releases/download/$C_VER/caddy_${C_VER}_linux_amd64.tar.gz"
echo ${CADDY_URL}
wget --no-check-certificate -qO 'caddy.tar.gz' ${CADDY_URL}
tar xvf caddy.tar.gz
rm -rf caddy.tar.gz
chmod +x caddy

cd /wwwroot
tar xvf wwwroot.tar.gz
rm -rf wwwroot.tar.gz

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
    "outbound":{
        "protocol":"freedom",
        "settings":{
        }
    },
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
http://0.0.0.0:${PORT}
{
	root /wwwroot
	index index.html
	timeouts none
	proxy ${V2_Path} localhost:2333 {
		websocket
		header_upstream -Origin
	}
  proxy / localhost:3333 {
    websocket
    header_upstream -Origin
  }
}
EOF

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

cd /v2raybin
./v2ray -config config.json &
cd /caddybin
./caddy -conf="Caddyfile"
