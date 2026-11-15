#!/usr/bin/env python3
"""Collects the Xbox 360 shader containers of your Forza Horizon (disc, Title
Update 4, installed DLC) that the native renderer's shader library is made
from, one file per distinct container, the way FH2 Recompiled's
tools/xenos/extrair_contenedores.py does for FH2.

They come from (ReImagined's tools/fxobj_shaders.py lists the same places):
  - the .fxobj files under media/ in the extracted game, and the ones inside
    its archives (the tracks' bin.zip: XMemCompress LZX, zip method 21, often
    without local headers);
  - the title update's media.zip (newer cars) and the installed DLC's
    archives;
  - the executables as loaded (the engine's own shaders), read with
    ReImagined's tools/xex_image.py.
A container is a 2008-format shader blob (0x102A1100 pixel, 0x102A1101
vertex): its virtual part followed by its physical part. They are written as
p_NNNNNN.bin / v_NNNNNN.bin with procedencia.tsv saying where each came from.

The speed blur's velocity shader gets ReImagined's fix for the sharp rectangle
around the car (platform/motion_blur_fix.cpp): ReImagined changes its stencil
threshold in the executable's image when the game starts, which the emulated
GPU reads, but the library's shaders carry their literal constants built in
(XenosRecomp writes them into the shader), so the same change is made here.
FORZA_BLUR_THRESHOLD=0 leaves it alone, as it does for ReImagined.

    extract-shader-containers.py OUT LZX_XMEM REIMAGINED_TOOLS SOURCE... [--xex XEX...]

OUT               a new folder
LZX_XMEM          FH2 Recompiled's tools/xenos/lzx_xmem built (libmspack)
REIMAGINED_TOOLS  ReImagined's tools/ folder (xex_image.py, lzx_delta.py)
SOURCE            folders or archives to search (missing ones are skipped)
XEX               executables whose loaded image is searched too
Nothing is written but OUT.
"""
import hashlib
import os
import struct
import subprocess
import sys
import tempfile
import zipfile


# The velocity pass's literal constants c252-c255, big-endian, as ReImagined's
# platform/motion_blur_fix.cpp looks for them. c253.w (0x3F008100, 128.0019 / 255)
# is the stencil threshold: just above 128 / 255, so the stencil-128 ground
# rectangle around the player's car counts as an object with an identity matrix
# and stays sharp while everything around it blurs. 0.5 puts 128 on the world side.
BLUR_LITERALS = struct.pack(
    ">16I",
    0xBF800000, 0x40A00000, 0x3EFEFEFF, 0x00000000,  # c252, .y = blur scale (5.0)
    0x35800000, 0x42AA0000, 0x40800000, 0x3F008100,  # c253, .w = the threshold
    0x3F800000, 0x3F000000, 0xC1700000, 0x417F0000,  # c254
    0x437F0000, 0x477F0000, 0x49800000, 0x3DCCCCCD)  # c255
BLUR_THRESHOLD_AT = 7 * 4
BLUR_THRESHOLD_FIXED = struct.pack(">I", 0x3F000000)  # 0.5


def fix_blur_threshold(blob):
    """(blob, True) with the speed blur's stencil threshold at 0.5 if blob is
    its velocity shader, else (blob, False)."""
    i = blob.find(BLUR_LITERALS)
    if i < 0:
        return blob, False
    fixed = bytearray(blob)
    fixed[i + BLUR_THRESHOLD_AT:i + BLUR_THRESHOLD_AT + 4] = BLUR_THRESHOLD_FIXED
    return bytes(fixed), True


def containers(data):
    """Yield (offset, kind, bytes) for every plausible 2008 shader container."""
    n, i = len(data), 0
    while True:
        i = data.find(b"\x10\x2a\x11", i)
        if i < 0 or i + 36 > n:
            return
        kind = data[i + 3]
        if kind > 1:
            i += 1
            continue
        _, virt, phys, _, ctab, _, desc = struct.unpack_from(">7I", data, i)
        if not (24 < virt and phys and virt + phys <= n - i and virt + phys <= 1 << 20
                and ctab < virt and desc < virt):
            i += 1
            continue
        yield i, "v" if kind else "p", bytes(data[i:i + virt + phys])
        i += virt + phys


class Lzx:
    def __init__(self, tool):
        self.tool = tool
        self.tmp = tempfile.mkdtemp(prefix="fh1-lzx-")
        self.failed = 0

    def decode(self, raw, size):
        """A method-21 member: frames [FF, uncompressed BE16, compressed BE16] or
        [compressed BE16], whose payloads make one LZX stream."""
        stream, p = bytearray(), 0
        while p < len(raw):
            if raw[p] == 0xFF:
                if p + 5 > len(raw):
                    break
                cs = struct.unpack_from(">H", raw, p + 3)[0]
                p += 5
            else:
                if p + 2 > len(raw):
                    break
                cs = struct.unpack_from(">H", raw, p)[0]
                p += 2
            if cs == 0 or p + cs > len(raw):
                break
            stream += raw[p:p + cs]
            p += cs
        src, dst = os.path.join(self.tmp, "in"), os.path.join(self.tmp, "out")
        with open(src, "wb") as f:
            f.write(stream)
        try:
            ok = subprocess.run([self.tool, src, str(size), dst], capture_output=True).returncode == 0
        except OSError:
            ok = False
        if not ok or not os.path.exists(dst):
            try:  # ReImagined's decoder, in Python (slower)
                import lzx_delta
                return bytes(lzx_delta.decompress(bytes(stream), size, 1 << 17))
            except Exception:
                self.failed += 1
                return None
        with open(dst, "rb") as f:
            data = f.read()
        os.remove(dst)
        return data


def member(path, fh, zf, info, lzx):
    """A zip member's bytes. The tracks' archives have no local headers: the
    central directory points straight at the data."""
    if info.compress_type not in (zipfile.ZIP_STORED, 21):
        try:
            return zf.read(info)
        except Exception:
            return None
    fh.seek(info.header_offset)
    h = fh.read(30)
    start = info.header_offset
    if h[:4] == b"PK\x03\x04":
        start += 30 + struct.unpack_from("<H", h, 26)[0] + struct.unpack_from("<H", h, 28)[0]
    fh.seek(start)
    raw = fh.read(info.compress_size)
    if info.compress_type == zipfile.ZIP_STORED:
        return raw
    return lzx.decode(raw, info.file_size)


def sources(paths):
    """Every .fxobj and .zip file under the sources, in a stable order."""
    for src in paths:
        if os.path.isdir(src):
            for root, dirs, files in os.walk(src):
                dirs.sort()
                for name in sorted(files):
                    if name.lower().endswith((".fxobj", ".zip")):
                        yield from sources([os.path.join(root, name)])
        elif os.path.isfile(src):
            yield src


def main():
    args = sys.argv[1:]
    xexes = []
    if "--xex" in args:
        k = args.index("--xex")
        args, xexes = args[:k], args[k + 1:]
    if len(args) < 4:
        sys.exit(__doc__)
    out, tool, tools_dir, srcs = args[0], args[1], args[2], args[3:]
    os.makedirs(out)
    sys.path.insert(0, tools_dir)
    lzx = Lzx(tool)
    seen = set()
    count = {"p": 0, "v": 0}
    files = archives = dup = images = blur = 0
    fix_blur = os.environ.get("FORZA_BLUR_THRESHOLD") != "0"
    idx = open(os.path.join(out, "procedencia.tsv"), "w")
    idx.write("archivo\torigen\tdesplazamiento\tvirtual\tfisico\n")

    def take(origin, data):
        nonlocal dup, blur
        for off, kind, blob in containers(data):
            if fix_blur and kind == "p":
                blob, fixed = fix_blur_threshold(blob)
                blur += fixed
            h = hashlib.sha1(blob).digest()
            if h in seen:
                dup += 1
                continue
            seen.add(h)
            name = "%s_%06d.bin" % (kind, len(seen) - 1)
            with open(os.path.join(out, name), "wb") as f:
                f.write(blob)
            virt, phys = struct.unpack_from(">II", blob, 4)
            idx.write("%s\t%s\t%d\t%d\t%d\n" % (name, origin, off, virt, phys))
            count[kind] += 1

    for path in sources(srcs):
        if path.lower().endswith(".fxobj"):
            with open(path, "rb") as f:
                take(path, f.read())
            files += 1
            continue
        try:
            zf = zipfile.ZipFile(path)
        except (zipfile.BadZipFile, OSError):
            continue
        with open(path, "rb") as fh:
            found = False
            for info in zf.infolist():
                if not info.filename.lower().endswith(".fxobj"):
                    continue
                data = member(path, fh, zf, info, lzx)
                if data:
                    take(path + "!" + info.filename, data)
                    files += 1
                    found = True
            archives += found

    if xexes:
        import xex_image  # ReImagined's
        for xex in xexes:
            if not os.path.isfile(xex):
                continue
            try:
                _, image = xex_image.load_image(xex)
            except (SystemExit, Exception) as e:  # an encrypted facade without openssl, say
                print("warning: %s not read: %s" % (xex, e))
                continue
            take(os.path.basename(xex) + " (image)", image)
            images += 1
    idx.close()
    print("shader containers: %d pixel, %d vertex (%d repeated) from %d .fxobj files in %d archives and %d "
          "executables%s" % (count["p"], count["v"], dup, files, archives, images,
                             ", %d archive entries not decompressed" % lzx.failed if lzx.failed else ""))
    if not count["p"] and not count["v"]:
        sys.exit("error: no shader container found")
    if not fix_blur:
        print("speed blur: stencil threshold left as is (FORZA_BLUR_THRESHOLD=0)")
    elif blur:
        print("speed blur: stencil threshold set to 0.5 in %d velocity shader(s), as ReImagined does" % blur)
    else:
        print("warning: speed blur velocity shader not found; the rectangle around the car stays sharp")


if __name__ == "__main__":
    main()
