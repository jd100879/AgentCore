"""Clean Python example: context managers and safe subprocess APIs."""

import pathlib
import shutil


def read_config(path: pathlib.Path) -> str:
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read()


def write_temp(paths: list[pathlib.Path]) -> None:
    for p in paths:
        with open(p, "w", encoding="utf-8") as fh:
            fh.write("ok")


def delete_path(path: pathlib.Path) -> None:
    if path.is_dir():
        shutil.rmtree(path)
    else:
        try:
            path.unlink()
        except FileNotFoundError:
            pass
