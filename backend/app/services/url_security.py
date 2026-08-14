"""
URL 安全校验 - 防止 SSRF。
校验规则：
  1. 仅允许 http/https scheme
  2. 解析域名并检查所有解析结果，拒绝危险网段
     （私网 RFC1918 / 回环 / 链路本地(含云元数据 169.254.169.254) /
       CGNAT / 未指定 / 组播 / 文档段等）
  3. 拒绝带用户信息（userinfo）的 URL
  4. 可通过环境变量 CLIPVAULT_EXTRA_BLOCKED_CIDRS 追加额外拦截网段
"""

import logging
import os
import socket
from ipaddress import ip_address, ip_network
from urllib.parse import urlparse

logger = logging.getLogger(__name__)

ALLOWED_SCHEMES = {"http", "https"}

# 平台标识白名单（用于 Cookie 文件名等拼接场景）
PLATFORM_RE = __import__("re").compile(r"^[a-z0-9_-]+$")


class UnsafeUrlError(ValueError):
    """URL 不符合安全策略"""


# 默认拦截网段（均为非公网/危险地址）
_BLOCKED_NETWORKS = [
    ip_network("0.0.0.0/8"),        # "this" network
    ip_network("10.0.0.0/8"),       # 私网
    ip_network("100.64.0.0/10"),    # CGNAT
    ip_network("127.0.0.0/8"),      # 回环
    ip_network("169.254.0.0/16"),   # 链路本地（含云元数据 169.254.169.254）
    ip_network("172.16.0.0/12"),    # 私网
    ip_network("192.0.0.0/24"),     # IETF 协议保留
    ip_network("192.0.2.0/24"),     # 文档示例
    ip_network("192.168.0.0/16"),   # 私网
    ip_network("192.88.99.0/24"),   # 6to4 中继
    ip_network("198.51.100.0/24"),  # 文档示例
    ip_network("203.0.113.0/24"),   # 文档示例
    ip_network("224.0.0.0/4"),      # 组播
    ip_network("240.0.0.0/4"),      # 保留
    ip_network("255.255.255.255/32"),
    ip_network("::/128"),
    ip_network("::1/128"),          # 回环
    ip_network("64:ff9b::/96"),     # NAT64
    ip_network("100::/64"),         # 丢弃前缀
    ip_network("2001:db8::/32"),    # 文档示例
    ip_network("fc00::/7"),         # ULA
    ip_network("fe80::/10"),        # 链路本地
    ip_network("ff00::/8"),         # 组播
]

for _extra in (os.getenv("CLIPVAULT_EXTRA_BLOCKED_CIDRS") or "").split(","):
    _extra = _extra.strip()
    if _extra:
        try:
            _BLOCKED_NETWORKS.append(ip_network(_extra))
        except ValueError:
            logger.warning("无效的拦截网段: %s", _extra)


def validate_platform(platform: str) -> bool:
    """平台标识是否安全（可安全用于文件路径拼接）"""
    return bool(PLATFORM_RE.fullmatch(platform or ""))


def resolve_hosts(hostname: str) -> list[str]:
    """解析域名，返回所有 IP 字符串。解析失败返回空列表。"""
    try:
        infos = socket.getaddrinfo(hostname, None, type=socket.SOCK_STREAM)
    except socket.gaierror:
        return []
    ips = [info[4][0] for info in infos]
    return list(dict.fromkeys(ips))


def _is_blocked(ip_str: str) -> bool:
    addr = ip_address(ip_str.split("%")[0])
    return any(addr in net for net in _BLOCKED_NETWORKS)


def check_target_url(url: str) -> str:
    """
    校验 URL 是否允许服务端抓取。
    返回规范化后的 URL；不安全时抛出 UnsafeUrlError。
    """
    if not url or len(url) > 4096:
        raise UnsafeUrlError("URL 无效")

    parsed = urlparse(url)
    if parsed.scheme.lower() not in ALLOWED_SCHEMES:
        raise UnsafeUrlError("仅允许 http/https 链接")

    if parsed.username or parsed.password:
        raise UnsafeUrlError("URL 不能包含用户信息")

    host = parsed.hostname
    if not host:
        raise UnsafeUrlError("URL 缺少主机名")

    # 排除明显的主机名注入
    if any(c in host for c in ("\\", "/")):
        raise UnsafeUrlError("URL 主机名无效")

    ips = resolve_hosts(host)
    if not ips:
        raise UnsafeUrlError("无法解析目标域名")

    for ip_str in ips:
        try:
            blocked = _is_blocked(ip_str)
        except ValueError:
            raise UnsafeUrlError(f"IP 地址无效: {ip_str}")
        if blocked:
            raise UnsafeUrlError(f"禁止访问非公网地址: {ip_str}")

    return url
