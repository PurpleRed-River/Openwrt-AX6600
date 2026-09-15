#!/usr/bin/env python3
"""在 squashfs 固件镜像的元数据区里直接搜字符串，确认文件是否真的被打进固件。

## 何时用

当"某个包/文件到底进固件了没有"需要证据时。实际踩过的坑：
  · luci-app-mwan3 因 Makefile 的 `include ../../luci.mk` 相对路径写错而编译失败，
    结果【后端 mwan3 进了固件、前端界面没进】—— 只看 release 的 manifest 能发现
    包名缺失，但若怀疑"包装了却没生效"，就需要直接查镜像。
  · NSS 页面、无线固化等改动是否真的落进镜像。

比 7z/unsquashfs 省事：纯 Python 标准库（可选 zstandard），无需安装、不受环境限制。

## 原理

squashfs 的目录项名字（dir entry name）在【元数据块】里是明文，元数据块整体可能被
xz/gzip/zstd 压缩。本脚本从 `inode_table_start` 起逐块按 2 字节头（低 15 位 = 长度，
bit15 = 未压缩）推进并解压，拼出文本流后搜关键字 —— 绕过 inode 引用解析，
对"文件在不在"足够可靠。

## 用法

    # 1) 下载固件（sysupgrade 或 factory 均可）
    # 2) 切出 squashfs（superblock 魔数 hsqs）
    python - <<'EOF'
    d = open('fw.bin','rb').read(); i = d.find(b'hsqs')
    open('root.sqfs','wb').write(d[i:])
    EOF
    # 3) 搜关键字
    python Scripts/sqfs-grep.py root.sqfs mwan3 components.js luci-app-mwan3.json

输出给出每个关键字的出现次数与一处上下文。上下文里能看出同目录的其它文件名，
据此判断是"路径结构正确"还是"只是名字碰巧出现"。

## 注意

遇到第一个不可识别的块就停止（说明已走出元数据区），所以次数是【下界】而非全量。
要更精确的清单，用 `7z l root.sqfs` 或 `unsquashfs -l`（若有）。
"""

import sys
import struct
import lzma
import zlib

COMP_GZIP, COMP_LZMA, COMP_LZO, COMP_XZ, COMP_LZ4, COMP_ZSTD = 1, 2, 3, 4, 5, 6


def decompress(data, comp_id):
    """尝试按压缩器解压；失败返回 None（表示可能未压缩）。"""
    if comp_id == COMP_XZ or comp_id == COMP_LZMA:
        try:
            return lzma.decompress(data)
        except Exception:
            pass
    if comp_id == COMP_GZIP:
        try:
            return zlib.decompress(data)
        except Exception:
            pass
        try:
            return zlib.decompressobj(-zlib.MAX_WBITS).decompress(data)
        except Exception:
            pass
    if comp_id == COMP_ZSTD:
        try:
            import zstandard
            return zstandard.ZstdDecompressor().decompress(data)
        except Exception:
            pass
    return None


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    path, keys = sys.argv[1], sys.argv[2:]

    d = open(path, 'rb').read()
    f = struct.unpack('<4sIIIIHHHHHHQQQQQQQQ', d[:96])
    comp = f[5]
    inode_tbl, bytes_used = f[15], f[12]

    # 元数据区从 inode_table_start 开始，到镜像数据结束
    pos = inode_tbl
    chunks = []
    blocks = 0
    while pos + 2 <= min(bytes_used, len(d)):
        hdr = struct.unpack('<H', d[pos:pos + 2])[0]
        stored = bool(hdr & 0x8000)
        ln = hdr & 0x7FFF
        if ln == 0:
            break
        payload = d[pos + 2:pos + 2 + ln]
        if len(payload) < ln:
            break
        if stored:
            out = payload
        else:
            out = decompress(payload, comp)
            if out is None:
                # 不是可识别压缩块 —— 说明已走出元数据区，停止
                break
        chunks.append(out)
        blocks += 1
        pos += 2 + ln

    blob = b'\x00'.join(chunks)
    print(f'  元数据区: {blocks} 块, 解压后共 {len(blob)} 字节 (comp={comp})')
    print()

    for k in keys:
        kb = k.encode()
        cnt = blob.count(kb)
        print(f'  ══ "{k}": 出现 {cnt} 次')
        if cnt:
            # 打印首次出现的上下文，便于辨认是路径还是碰巧
            i = blob.find(kb)
            ctx = blob[max(0, i - 60):i + 60]
            printable = ''.join(chr(c) if 32 <= c < 127 else '.' for c in ctx)
            print(f'     上下文: …{printable}…')
    return 0


if __name__ == '__main__':
    sys.exit(main())
