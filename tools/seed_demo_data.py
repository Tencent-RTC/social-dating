#!/usr/bin/env python3
import argparse
import base64
import getpass
import hashlib
import hmac
import json
import os
import random
import sys
import threading
import time
import urllib.error
import urllib.request
import zlib
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_DATA = HERE / "seed_demo_data.json"
ENV_APPID = "CHAT1V1_SDKAPPID"
ENV_SECRET = "CHAT1V1_SECRETKEY"
REGIONS = {
    "cn": "console.tim.qq.com",
    "sgp": "adminapisgp.im.qcloud.com",
    "kr": "adminapikr.im.qcloud.com",
    "jpn": "adminapijpn.im.qcloud.com",
    "ger": "adminapiger.im.qcloud.com",
    "usa": "adminapiusa.im.qcloud.com",
    "idn": "adminapiidn.im.qcloud.com",
    "ksa": "adminapiksa.im.qcloud.com",
}
AUTH_HINTS = {
    70001: "UserSig 已过期，请检查本机时间是否准确。",
    70003: "UserSig 解析失败，请检查 SecretKey 是否完整。",
    70009: "SecretKey 与 SDKAppID 不匹配，请到 IM 控制台确认两者属于同一个应用。",
    70016: "找不到该应用的密钥：请确认 SDKAppID 正确；海外应用请用 --region 指定数据中心。",
    70020: "SDKAppID 不存在：请确认 SDKAppID 正确；海外应用请用 --region 指定数据中心。",
    70050: "UserSig 校验失败次数过多，请 1 分钟后再试。",
    70403: "--admin 指定的账号不是 App 管理员，请在 IM 控制台查看管理员账号后用 --admin 指定。",
}
ACCOUNT_HINTS = {
    70398: "应用的账号数已达上限，请在 IM 控制台升级套餐。",
    80001: "资料中包含被拦截的敏感词。",
}
RETRYABLE = {30006, 30007, 40006, 70169, 70202, 70500, 90992, 91000}
GENDERS = {"m": "Gender_Type_Male", "f": "Gender_Type_Female"}
FRIEND_PRESENT = {"CheckResult_Type_BothWay", "CheckResult_Type_AWithB"}
DAILY_MESSAGE_LIMIT = 1000
WORKERS = 6
CERT_HINT = (
    "HTTPS 证书校验失败。macOS 上使用 python.org 安装包的 Python 时，"
    "请先运行「/Applications/Python 3.x/Install Certificates.command」后重试。"
)


class SeedError(Exception):
    pass


def gen_usersig(appid, secret, identifier, expire=86400):
    now = int(time.time())
    content = "TLS.identifier:%s\nTLS.sdkappid:%d\nTLS.time:%d\nTLS.expire:%d\n" % (identifier, appid, now, expire)
    sig = base64.b64encode(hmac.new(secret.encode(), content.encode(), hashlib.sha256).digest()).decode()
    doc = {
        "TLS.ver": "2.0",
        "TLS.identifier": identifier,
        "TLS.sdkappid": appid,
        "TLS.expire": expire,
        "TLS.time": now,
        "TLS.sig": sig,
    }
    raw = zlib.compress(json.dumps(doc, separators=(",", ":")).encode())
    return base64.b64encode(raw).decode().replace("+", "*").replace("/", "-").replace("=", "_")


class Rest:
    def __init__(self, domain, appid, secret, admin):
        self.domain = domain
        self.appid = appid
        self.admin = admin
        self.sig = gen_usersig(appid, secret, admin)

    def call(self, path, body):
        problem = ""
        for attempt in range(3):
            url = "https://%s/%s?sdkappid=%d&identifier=%s&usersig=%s&random=%d&contenttype=json" % (
                self.domain, path, self.appid, self.admin, self.sig, random.randint(1, 2**32 - 1)
            )
            req = urllib.request.Request(url, data=json.dumps(body).encode("utf-8"),
                                         headers={"Content-Type": "application/json"})
            try:
                with urllib.request.urlopen(req, timeout=20) as resp:
                    result = json.loads(resp.read().decode("utf-8"))
            except urllib.error.HTTPError as e:
                problem = "HTTP %d" % e.code
            except urllib.error.URLError as e:
                if "CERTIFICATE_VERIFY_FAILED" in str(e.reason):
                    raise SeedError(CERT_HINT)
                problem = str(e.reason)
            except (OSError, ValueError) as e:
                problem = str(e)
            else:
                if result.get("ErrorCode") in RETRYABLE and attempt < 2:
                    problem = "ErrorCode=%s" % result.get("ErrorCode")
                else:
                    return result
            time.sleep(1 + attempt)
        raise SeedError("请求 %s 失败：%s。请检查网络后重新运行。" % (self.domain, problem))


def load_data(path):
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        raise SeedError("读取演示数据失败（%s）：%s" % (path, e))
    users = data.get("users") or []
    ids = [u.get("userID") for u in users]
    known = set(ids)
    problems = []
    if not users or len(known) != len(ids) or None in known:
        problems.append("users 为空或 userID 重复")
    for pair in data.get("friends", []):
        if len(pair) != 2 or pair[0] == pair[1] or not set(pair) <= known:
            problems.append("好友关系 %s 无效" % pair)
    for conv in data.get("conversations", []):
        pair = conv.get("between") or []
        if len(pair) != 2 or not set(pair) <= known:
            problems.append("会话 %s 无效" % pair)
            continue
        for sender, _ in conv.get("messages", []):
            if sender not in pair:
                problems.append("会话 %s 的发送者 %s 不在会话中" % (pair, sender))
    for uid in data.get("loginAccounts", []):
        if uid not in known:
            problems.append("登录账号 %s 不在 users 中" % uid)
    if problems:
        raise SeedError("演示数据格式错误：" + "；".join(problems[:5]))
    return data


def parse_sdkappid(raw, label):
    try:
        value = int(str(raw).strip())
    except ValueError:
        raise SeedError("%s 必须是正整数" % label)
    if value <= 0:
        raise SeedError("%s 必须是正整数" % label)
    return value


def resolve_credentials(args):
    interactive = sys.stdin.isatty()
    sources = []

    if args.sdkappid is not None:
        appid = parse_sdkappid(args.sdkappid, "--sdkappid")
        sources.append("命令行参数")
    else:
        env_appid = os.environ.get(ENV_APPID, "").strip()
        if env_appid:
            appid = parse_sdkappid(env_appid, "环境变量 %s" % ENV_APPID)
            sources.append("环境变量")
        else:
            if not interactive:
                raise SeedError("缺少 SDKAppID：请通过 --sdkappid 或环境变量 %s 提供" % ENV_APPID)
            try:
                raw_appid = input("SDKAppID: ")
            except EOFError:
                raise SeedError("未输入 SDKAppID，已取消。")
            appid = parse_sdkappid(raw_appid, "SDKAppID")
            sources.append("手动输入")

    secret = os.environ.get(ENV_SECRET, "").strip()
    if secret:
        sources.append("环境变量")
    else:
        if not interactive:
            raise SeedError("缺少 SecretKey：请通过环境变量 %s 提供（或在交互终端运行手动输入）" % ENV_SECRET)
        try:
            secret = getpass.getpass("SecretKey（输入时不显示）: ").strip()
        except EOFError:
            raise SeedError("未输入 SecretKey，已取消。")
        if not secret:
            raise SeedError("SecretKey 不能为空")
        sources.append("手动输入")

    return appid, secret, " / ".join(dict.fromkeys(sources))


def asset_url(asset_base, path):
    if path.startswith("http://") or path.startswith("https://"):
        return path
    return "%s/%s" % (asset_base, path.lstrip("/"))


def adjacency(data):
    adj = {u["userID"]: [] for u in data["users"]}
    for a, b in data.get("friends", []):
        adj[a].append(b)
        adj[b].append(a)
    return {k: sorted(set(v)) for k, v in adj.items()}


def friend_pairs(data):
    return {tuple(sorted(p)) for p in data.get("friends", [])}


def message_count(convs):
    return sum(len(c["messages"]) for c in convs)


class Progress:
    def __init__(self, label, total):
        self.label = label
        self.total = total
        self.live = sys.stdout.isatty()

    def update(self, done):
        if self.live:
            print("\r  %s %d/%d" % (self.label, done, self.total), end="", flush=True)

    def clear(self):
        if self.live:
            print("\r" + " " * 40 + "\r", end="", flush=True)

    def finish(self, text):
        self.clear()
        print("  " + text)


def parallel(label, items, fn):
    progress = Progress(label, len(items))
    results = [None] * len(items)
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        futures = {pool.submit(fn, item): i for i, item in enumerate(items)}
        for n, future in enumerate(as_completed(futures), 1):
            results[futures[future]] = future.result()
            progress.update(n)
    progress.clear()
    return results


def check_auth(rest, ids):
    imported = set()
    for start in range(0, len(ids), 100):
        r = rest.call("v4/im_open_login_svc/account_check",
                      {"CheckItem": [{"UserID": i} for i in ids[start:start + 100]]})
        code = r.get("ErrorCode")
        if code != 0:
            hint = AUTH_HINTS.get(code, "")
            raise SeedError("鉴权失败：ErrorCode=%s %s%s" % (code, r.get("ErrorInfo", ""), "\n提示：" + hint if hint else ""))
        imported |= {x.get("UserID") for x in r.get("ResultItem", []) if x.get("AccountStatus") == "Imported"}
    return imported


def profile_items(user, asset_base):
    items = [
        {"Tag": "Tag_Profile_IM_Nick", "Value": user["nickname"]},
        {"Tag": "Tag_Profile_IM_Image", "Value": asset_url(asset_base, user["avatar"])},
        {"Tag": "Tag_Profile_IM_SelfSignature", "Value": user.get("signature", "")},
        {"Tag": "Tag_Profile_IM_Gender", "Value": GENDERS.get(user.get("gender"), "Gender_Type_Unknown")},
        {"Tag": "Tag_Profile_IM_AllowType", "Value": "AllowType_Type_AllowAny"},
    ]
    if user.get("age"):
        items.append({"Tag": "Tag_Profile_IM_BirthDay", "Value": (date.today().year - int(user["age"])) * 10000 + 101})
    return items


def seed_accounts(rest, users, asset_base):
    progress = Progress("账号", len(users))
    failed = []
    for n, u in enumerate(users, 1):
        uid = u["userID"]
        r = rest.call("v4/im_open_login_svc/account_import",
                      {"UserID": uid, "Nick": u["nickname"], "FaceUrl": asset_url(asset_base, u["avatar"])})
        if r.get("ErrorCode") == 0:
            r = rest.call("v4/profile/portrait_set", {"From_Account": uid, "ProfileItem": profile_items(u, asset_base)})
        if r.get("ErrorCode") != 0:
            failed.append((uid, r.get("ErrorCode"), r.get("ErrorInfo", "")))
            if n == 1:
                break
        progress.update(n)
    if failed:
        progress.finish("账号写入失败 %d 个：" % len(failed))
        for uid, code, info in failed[:5]:
            print("    %s ErrorCode=%s %s %s" % (uid, code, info, ACCOUNT_HINTS.get(code, "")))
        raise SeedError("账号写入失败，已停止。")
    progress.finish("账号：%d 个已就绪（昵称、头像、签名、性别）" % len(users))


def missing_friends(rest, adj):
    def check(item):
        uid, expected = item
        r = rest.call("v4/sns/friend_check",
                      {"From_Account": uid, "To_Account": expected, "CheckType": "CheckResult_Type_Both"})
        if r.get("ErrorCode") != 0:
            return uid, list(expected)
        present = {x.get("To_Account") for x in r.get("InfoItem", [])
                   if x.get("ResultCode") == 0 and x.get("Relation") in FRIEND_PRESENT}
        return uid, [f for f in expected if f not in present]

    items = [(uid, expected) for uid, expected in adj.items() if expected]
    return {uid: lack for uid, lack in parallel("检查好友", items, check) if lack}


def seed_friends(rest, data):
    total = len(friend_pairs(data))
    plan = missing_friends(rest, adjacency(data))
    if not plan:
        print("  好友：%d 对已存在，跳过" % total)
        return
    progress = Progress("好友", len(plan))
    failed = []
    for n, (uid, targets) in enumerate(sorted(plan.items()), 1):
        r = rest.call("v4/sns/friend_import", {
            "From_Account": uid,
            "AddFriendItem": [{"To_Account": t, "AddSource": "AddSource_Type_Demo"} for t in targets],
        })
        if r.get("ErrorCode") != 0:
            failed.append((uid, r.get("ErrorCode"), r.get("ErrorInfo", "")))
        else:
            for item in r.get("ResultItem", []):
                if item.get("ResultCode") != 0:
                    failed.append(("%s → %s" % (uid, item.get("To_Account")), item.get("ResultCode"), item.get("ResultInfo", "")))
        progress.update(n)
    if failed:
        progress.finish("好友写入失败 %d 条：" % len(failed))
        for who, code, info in failed[:5]:
            print("    %s ErrorCode=%s %s" % (who, code, info))
        raise SeedError("好友关系写入失败，已停止。")
    progress.finish("好友：%d 对已就绪" % total)


def history_count(rest, conv):
    a, b = conv["between"]
    r = rest.call("v4/openim/admin_getroammsg", {
        "Operator_Account": a, "Peer_Account": b, "MaxCnt": len(conv["messages"]),
        "MinTime": 0, "MaxTime": int(time.time()) + 3600,
    })
    return len(r.get("MsgList") or []) if r.get("ErrorCode") == 0 else 0


def pending_conversations(rest, convs):
    counts = parallel("检查会话", convs, lambda c: history_count(rest, c))
    return [(c, n) for c, n in zip(convs, counts) if n < len(c["messages"])]


def send_conversation(rest, conv, start, stop):
    a, b = conv["between"]
    seq = random.randint(10000, 2**30)
    sent = 0
    for sender, text in conv["messages"][start:]:
        if stop.is_set():
            break
        receiver = b if sender == a else a
        seq += 1
        r = rest.call("v4/openim/sendmsg", {
            "SyncOtherMachine": 1,
            "From_Account": sender,
            "To_Account": receiver,
            "MsgSeq": seq,
            "MsgRandom": random.randint(1, 2**32 - 1),
            "ForbidCallbackControl": ["ForbidBeforeSendMsgCallback", "ForbidAfterSendMsgCallback"],
            "MsgBody": [{"MsgType": "TIMTextElem", "MsgContent": {"Text": text}}],
        })
        if r.get("ErrorCode") != 0:
            stop.set()
            return sent, (sender, receiver, r.get("ErrorCode"), r.get("ErrorInfo", ""))
        sent += 1
        time.sleep(0.1)
    return sent, None


def seed_messages(rest, convs):
    pending = pending_conversations(rest, convs)
    if not pending:
        print("  会话：%d 个已完整，跳过" % len(convs))
        return
    progress = Progress("消息", sum(len(c["messages"]) - n for c, n in pending))
    stop = threading.Event()
    sent = 0
    errors = []
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        futures = [pool.submit(send_conversation, rest, conv, n, stop) for conv, n in pending]
        for future in as_completed(futures):
            count, error = future.result()
            sent += count
            if error:
                errors.append(error)
            progress.update(sent)
    if errors:
        progress.finish("已发送 %d 条" % sent)
        sender, receiver, code, info = errors[0]
        raise SeedError(
            "发送消息失败（%s → %s）：ErrorCode=%s %s\n"
            "体验版和开发版每天最多通过 REST API 发送 %d 条单聊消息。处理后重新运行即可，会从中断的地方继续。"
            % (sender, receiver, code, info, DAILY_MESSAGE_LIMIT)
        )
    skipped = len(convs) - len(pending)
    progress.finish("会话：写入 %d 个（%d 条消息）%s" % (len(pending), sent, "，%d 个已完整跳过" % skipped if skipped else ""))


def verify(rest, data, existing=None):
    ids = [u["userID"] for u in data["users"]]
    if existing is None:
        existing = check_auth(rest, ids)
    accounts_ok = sum(1 for i in ids if i in existing)
    pairs = friend_pairs(data)
    lack = missing_friends(rest, adjacency(data)) if accounts_ok else {u: v for u, v in adjacency(data).items() if v}
    broken = {tuple(sorted((u, f))) for u, fs in lack.items() for f in fs}
    convs = data.get("conversations", [])
    conv_ok = len(convs) - len(pending_conversations(rest, convs)) if accounts_ok else 0
    print("  账号 %d/%d，好友 %d/%d 对，会话 %d/%d 个" % (
        accounts_ok, len(ids), len(pairs) - len(broken & pairs), len(pairs), conv_ok, len(convs)))
    return accounts_ok == len(ids) and not (broken & pairs) and conv_ok == len(convs)


def login_overview(data):
    names = {u["userID"]: u["nickname"] for u in data["users"]}
    adj = adjacency(data)
    pairs = friend_pairs(data)
    lines = []
    for uid in data.get("loginAccounts", []):
        convs = [c for c in data.get("conversations", []) if uid in c["between"]]
        greet = sum(1 for c in convs if tuple(sorted(c["between"])) not in pairs)
        text = "  %s  %s：%d 个好友，%d 个会话" % (uid, names[uid], len(adj[uid]), len(convs) - greet)
        if greet:
            text += "，%d 条打招呼" % greet
        lines.append(text)
    return lines


def confirm(args, appid):
    if args.yes:
        return True
    if not sys.stdin.isatty():
        raise SeedError("当前不是交互终端，请加 --yes 确认写入。")
    try:
        answer = input("将在 SDKAppID %d 下写入以上演示数据，继续吗？[y/N] " % appid).strip().lower()
    except EOFError:
        return False
    return answer in ("y", "yes")


def build_parser():
    ap = argparse.ArgumentParser(
        description="把 Chat1v1 演示数据（账号、资料、好友、会话）导入您自己的 IM 应用。"
        "SDKAppID 可通过 --sdkappid 或环境变量 %s 提供，SecretKey 可通过环境变量 %s 提供；"
        "未提供时在终端提示输入。" % (ENV_APPID, ENV_SECRET)
    )
    ap.add_argument("--sdkappid", type=int, default=None,
                    help="应用的 SDKAppID（也可通过环境变量 %s 提供）" % ENV_APPID)
    ap.add_argument("--region", choices=sorted(REGIONS), default="cn",
                    help="应用所在数据中心，默认 cn（中国）；海外应用填 sgp、kr、jpn、ger、usa、idn 或 ksa")
    ap.add_argument("--admin", default="administrator", help="App 管理员账号，默认 administrator")
    ap.add_argument("--data", default=str(DEFAULT_DATA), help="演示数据文件，默认取脚本同目录的 seed_demo_data.json")
    ap.add_argument("--asset-base", default="", help="头像地址前缀，默认取数据文件中的 assetBase")
    ap.add_argument("--skip-messages", action="store_true", help="只导入账号和好友，不发送示例消息")
    ap.add_argument("--dry-run", action="store_true", help="只显示将要导入的内容，不连接 IM")
    ap.add_argument("--verify", action="store_true", help="只检查演示数据是否已导入，不写入")
    ap.add_argument("--yes", "-y", action="store_true", help="不再询问，直接写入")
    return ap


def run(args):
    data = load_data(args.data)
    asset_base = (args.asset_base or data.get("assetBase", "")).rstrip("/")
    users = data["users"]
    if not asset_base and any(
        not (u["avatar"].startswith("http://") or u["avatar"].startswith("https://")) for u in users
    ):
        raise SeedError("缺少头像地址前缀：请在数据文件中设置 assetBase，或通过 --asset-base 指定")
    convs = data.get("conversations", [])
    print("演示数据：%d 个账号、%d 对好友、%d 个会话（%d 条消息）" % (
        len(users), len(friend_pairs(data)), len(convs), message_count(convs)))
    if args.dry_run:
        print("头像地址：%s/..." % asset_base)
        print("可登录的账号：")
        print("\n".join(login_overview(data)))
        print("（--dry-run：没有连接 IM，也没有写入任何数据）")
        return 0

    appid, secret, source = resolve_credentials(args)
    domain = REGIONS[args.region]
    print("SDKAppID：%d（凭据来源：%s），数据中心：%s" % (appid, source, domain))
    rest = Rest(domain, appid, secret, args.admin)
    existing = check_auth(rest, [u["userID"] for u in users])
    print("鉴权通过，应用中已有 %d/%d 个演示账号" % (len(existing), len(users)))

    if args.verify:
        ok = verify(rest, data, existing)
        print("演示数据完整" if ok else "演示数据不完整，请去掉 --verify 重新运行脚本补齐")
        return 0 if ok else 1

    if not args.skip_messages and message_count(convs) > DAILY_MESSAGE_LIMIT:
        print("注意：消息数超过体验版和开发版每天 %d 条的发送上限，可能需要分两天运行。" % DAILY_MESSAGE_LIMIT)
    if not confirm(args, appid):
        print("已取消，没有写入任何数据。")
        return 1

    steps = 2 if args.skip_messages else 3
    print("[1/%d] 导入账号和资料" % steps)
    seed_accounts(rest, users, asset_base)
    print("[2/%d] 导入好友关系" % steps)
    seed_friends(rest, data)
    if not args.skip_messages:
        print("[3/%d] 发送示例消息（约 %d 条，需要一两分钟）" % (steps, message_count(convs)))
        seed_messages(rest, convs)

    print("\n完成！用下面的账号登录 App：")
    print("\n".join(login_overview(data)))
    print("这几个账号互为好友，两台设备各登录一个就能互相聊天、视频通话。")
    print("打招呼消息在「消息 → 打招呼消息」中查看（需要开发版、旗舰版或企业版）。")
    return 0


def main():
    args = build_parser().parse_args()
    try:
        return run(args)
    except SeedError as e:
        print("\n" + str(e), file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("\n已中断。重新运行即可从中断的地方继续。", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main())