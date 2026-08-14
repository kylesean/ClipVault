#!/usr/bin/env python3
"""
抖音核心算法同步脚本。

从上游 Douyin_TikTok_Download_API 仓库拉取核心文件到
backend/app/douyin_core/，方便在抖音改版（a_bogus 失效）后快速更新。

用法:
    python3 scripts/sync_douyin_core.py

注意:
    - 仅覆盖同步 abogus.py 与 config.yaml（算法与参数）
    - 下载的 config.yaml 会**自动剥离 Cookie 字段**（上游配置含真实 Cookie，
      不得进入本仓库；Cookie 统一由 backend/cookies/douyin.txt 提供）
    - token_manager/fetchers/models/crawler 为精简迁移代码，需人工比对
    - 同步后请用真实抖音链接验证: make dev 后 curl /api/parse
"""

import sys
from pathlib import Path
from urllib.request import urlretrieve

UPSTREAM = "https://raw.githubusercontent.com/Evil0ctal/Douyin_TikTok_Download_API/main/crawlers/douyin/web"
TARGET_DIR = Path(__file__).resolve().parent.parent / "backend" / "app" / "douyin_core"

# (上游文件名, 本地文件名, 是否需要剥离 Cookie)
FILES = [
    ("abogus.py", "abogus.py", False),
    ("config.yaml", "config.yaml", True),
]


def strip_cookie_fields(text: str) -> str:
    """移除 yaml 中的 Cookie 行（上游 config.yaml 含真实登录 Cookie，禁止入库）"""
    import re

    # 匹配 "  Cookie: ..." 整行（含内联值，可能很长）
    return re.sub(r"(?m)^\s*Cookie:.*\n", "", text)


def main() -> int:
    TARGET_DIR.mkdir(parents=True, exist_ok=True)
    ok = True
    for remote, local, strip in FILES:
        src = f"{UPSTREAM}/{remote}"
        dst = TARGET_DIR / local
        try:
            urlretrieve(src, dst)
            if strip:
                content = dst.read_text(encoding="utf-8")
                stripped = strip_cookie_fields(content)
                dst.write_text(stripped, encoding="utf-8")
                removed = content.count("Cookie:") - stripped.count("Cookie:")
                print(f"✓ {remote} -> {dst}（已剥离 {removed} 处 Cookie 字段）")
            else:
                print(f"✓ {remote} -> {dst}")
        except Exception as e:
            print(f"✗ {remote} 下载失败: {e}")
            ok = False

    print()
    if ok:
        print("同步完成。请验证:")
        print("  1. 启动服务: make dev")
        print("  2. POST /api/parse 测试真实抖音链接")
        print("  3. 若签名相关代码变更，同步 douyin_core 中其他文件（人工比对上游）")
    else:
        print("部分文件同步失败，请检查网络后重试。")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
