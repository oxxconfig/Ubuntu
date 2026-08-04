python3 -c '
import json
path = "/usr/local/etc/xray/config.json"
try:
    with open(path, "r") as f:
        d = json.load(f)
except:
    path = "/etc/xray/config.json"
    with open(path, "r") as f:
        d = json.load(f)

for ib in d.get("inbounds", []):
    if ib.get("streamSettings", {}).get("security") == "reality":
        rs = ib["streamSettings"]["realitySettings"]
        rs["dest"] = "mora.jp:443"
        rs["serverNames"] = ["mora.jp"]
        rs["shortIds"] = ["67d93779"]

with open(path, "w") as f:
    json.dump(d, f, indent=2)
' && systemctl restart xray
