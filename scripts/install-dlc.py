#!/usr/bin/env python3
"""Installs Forza Horizon DLC where the game built by build.sh finds it:
your own Microsoft packs and community ones such as the UDLC Pack (the Forza
Horizon 2 cars) and its Traffic Car Unlocker.

    scripts/install-dlc.py [--dir DIR] SOURCE...
    scripts/install-dlc.py [--dir DIR] --list

DIR     the build folder (default ~/.local/share/FH1ReImagined-arm64)
SOURCE  a .zip as downloaded (UDLCv1.2.zip, for instance), a DLC package
        file (named like 21D846F4D0EB47F4C4EB6892992F83429BBAD7D5), or a
        folder holding them: a Xenia content folder, its 4D5309C9 or
        00000002 folder, or any folder with packages somewhere inside

Each package is unpacked into DIR/user/0000000000000000/4D5309C9/00000002
with ReImagined's own tools/install_dlc.py (from the sources build.sh
checked out), which also writes the header that unlocks it. A package that
is already there is replaced. Close the game first. Removing DLC can leave a
save without a car it owned: keep a copy of DIR/user before you do.

Needs only Python's standard library.
"""
import argparse
import os
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

PACKAGE_MAGIC = (b"LIVE", b"PIRS", b"CON ")
TITLE = "4D5309C9"


def is_package(path: Path) -> bool:
    try:
        with path.open("rb") as f:
            return f.read(4) in PACKAGE_MAGIC
    except OSError:
        return False


def content(user: Path) -> Path:
    return user / "0000000000000000" / TITLE


def installed(user: Path) -> list[tuple[str, str]]:
    """(package name, display name) of the installed packages."""
    root = content(user) / "00000002"
    if not root.is_dir():
        return []
    result = []
    for p in sorted(root.iterdir()):
        if not p.is_dir() or p.name.endswith(".part"):
            continue
        name = p.name
        header = content(user) / "Headers" / "00000002" / (p.name + ".header")
        try:
            name = header.read_bytes()[8:264].decode("utf-16-be", "ignore").split("\0")[0].strip() or name
        except OSError:
            pass
        result.append((p.name, name))
    return result


def find(root: Path) -> tuple[list[Path], list[Path]]:
    """The 00000002 folders (extracted DLC, Xenia's layout) and the loose
    package files under root."""
    folders, files = [], []
    for here, dirs, names in os.walk(root):
        dirs.sort()
        dirs[:] = [d for d in dirs if d.lower() != "headers"]
        if Path(here).name.lower() == "00000002" and Path(here) != root:
            folders.append(Path(here))
            dirs[:] = []
            continue
        files += [Path(here) / n for n in sorted(names) if is_package(Path(here) / n)]
    return folders, files


def install_source(tool, source: Path, user: Path, scratch: Path) -> tuple[int, list[str]]:
    """Installs what source holds; returns (packages, problems)."""
    count, problems = 0, []
    if source.is_file() and zipfile.is_zipfile(source):
        unpacked = Path(tempfile.mkdtemp(prefix="dlc-", dir=scratch))
        try:
            print(f"Unpacking {source.name}")
            with zipfile.ZipFile(source) as z:
                z.extractall(unpacked)
            # A zip of zips (a pack and its add-on in one download), but not
            # the zips that are part of a package's own files.
            for inner in sorted(unpacked.rglob("*.zip")):
                parts = inner.relative_to(unpacked).parts[:-1]
                if any(part.lower() == "00000002" or tool.NAME_RE.fullmatch(part) for part in parts):
                    continue
                n, p = install_source(tool, inner, user, scratch)
                count, problems = count + n, problems + p
            n, p = install_source(tool, unpacked, user, scratch)
            if not count + n:
                problems.append(f"{source.name} holds no Forza Horizon DLC")
            return count + n, problems + p
        finally:
            shutil.rmtree(unpacked, ignore_errors=True)
    if source.is_file():
        if not is_package(source):
            return 0, [f"{source} is not a DLC package or a .zip (extract other archives first)"]
        try:
            damaged = tool.install(str(source), str(user))
        except (SystemExit, ValueError, OSError) as e:
            return 0, [f"{source.name}: {e}"]
        problems += [f"{source.name}: {path} is damaged: download it again" for path, _ in damaged]
        # install() skips, saying so, a package that is not DLC (a title update).
        return int((content(user) / "00000002" / source.name).is_dir()), problems
    if not source.is_dir():
        return 0, [f"{source} does not exist"]
    folders, files = find(source)
    if source.name.lower() == "00000002" or not (folders or files):
        # The 00000002 folder itself, or extracted package folders on their own.
        folders, files = [source], []
    for folder in folders:
        _root, dirs, loose, skipped = tool.scan_folder(str(folder))
        for f in loose:
            if is_package(Path(f)):
                n, p = install_source(tool, Path(f), user, scratch)
                count, problems = count + n, problems + p
        for d, name, display, header in dirs:
            dest = tool.install_folder(d, name, header, str(user), display_name=display)
            print(f"{display}: {tool.folder_size(d)} bytes -> {dest}")
            count += 1
        for name, why in skipped:
            print(f"skipping {name}: {why}")
    for f in files:
        n, p = install_source(tool, f, user, scratch)
        count, problems = count + n, problems + p
    return count, problems


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(usage=__doc__.split("\n\n")[1])
    parser.add_argument("--dir", type=Path, default=Path.home() / ".local/share/FH1ReImagined-arm64")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("sources", nargs="*")
    a = parser.parse_args(argv[1:])
    if not a.list and not a.sources:
        print(__doc__, file=sys.stderr)
        return 2
    data = a.dir.expanduser().resolve()
    user = data / "user"
    if a.list:
        packs = installed(user)
        for name, display in packs:
            print(f"{display} ({name})")
        print(f"{len(packs)} DLC package{'s' if len(packs) != 1 else ''} installed")
        return 0
    tools = data / "source" / "reimagined" / "tools"
    if not (tools / "install_dlc.py").is_file():
        sys.exit("error: build the game first: ReImagined's DLC installer comes with its sources")
    sys.path.insert(0, str(tools))
    import install_dlc as tool  # noqa: E402  (ReImagined's tools/install_dlc.py)

    user.mkdir(parents=True, exist_ok=True)
    total, problems = 0, []
    for source in a.sources:
        n, p = install_source(tool, Path(source).expanduser().resolve(), user, data)
        total, problems = total + n, problems + p
    for p in problems:
        print(f"error: {p}", file=sys.stderr)
    print(f"Installed {total} DLC package{'s' if total != 1 else ''}; "
          f"{len(installed(user))} in {content(user) / '00000002'}")
    return 1 if problems or not total else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
