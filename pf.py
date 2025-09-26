#!/usr/bin/env python3
# pf.py — tiny symbol‑free pyinfra-like runner for PhoenixGuard
# Executes tasks defined in Pfyfile.pf and included .pf files.
# Supported verbs inside a task:
#   describe <text>
#   shell <command...>
#   packages install|remove <names...>
#   service start|stop|enable|disable|restart <name>
#   directory <path> [mode=0755]
#   copy <local> <remote> [mode=0644] [user=...] [group=...]
# Top-level:
#   include <path.pf>
# CLI:
#   ./pf.py list
#   ./pf.py <task> [<task> ...]
# Notes:
#   - Defaults to local execution; host inventory is not implemented in this minimal runner.
#   - Environment variables are passed through, e.g. TAG, ASSETS, ISO_PATH, etc.

import os
import re
import shlex
import stat
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Tuple

REPO_ROOT = Path(__file__).resolve().parent
PFYFILE = REPO_ROOT / "Pfyfile.pf"

class Task:
    def __init__(self, name: str) -> None:
        self.name = name
        self.desc: str = ""
        self.actions: List[Tuple[str, List[str]]] = []  # (verb, args)

    def add(self, verb: str, args: List[str]) -> None:
        self.actions.append((verb, args))


def parse_pf(path: Path, seen: set) -> Dict[str, Task]:
    if path in seen:
        return {}
    seen.add(path)
    tasks: Dict[str, Task] = {}
    if not path.exists():
        raise FileNotFoundError(f"PF file not found: {path}")
    cur: Task = None  # type: ignore
    in_task = False

    def flush_task():
        nonlocal cur
        if cur:
            tasks[cur.name] = cur
        cur = None

    with path.open("r", encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line:
                continue
            # top-level include
            if not in_task and line.startswith("include"):
                inc = line[len("include") :].strip()
                inc = inc.strip('"')
                inc_path = (path.parent / inc).resolve()
                tasks.update(parse_pf(inc_path, seen))
                continue
            if line.startswith("task ") and not in_task:
                name = line[len("task ") :].strip()
                cur = Task(name)
                in_task = True
                continue
            if line == "end" and in_task:
                flush_task()
                in_task = False
                continue
            if in_task and cur:
                # shlex split, allow quoted args
                parts = shlex.split(line)
                if not parts:
                    continue
                verb, args = parts[0], parts[1:]
                if verb == "describe":
                    cur.desc = " ".join(args)
                else:
                    cur.add(verb, args)
            # else ignore unknown top-level lines
    if in_task:
        flush_task()
    return tasks


def load_tasks() -> Dict[str, Task]:
    if not PFYFILE.exists():
        print(f"ERROR: {PFYFILE} not found. Create it with 'include' lines and tasks.", file=sys.stderr)
        sys.exit(2)
    return parse_pf(PFYFILE, set())


def ensure_dir(path: Path, mode_str: str = "0755"):
    mode = int(mode_str, 8)
    path.mkdir(parents=True, exist_ok=True)
    os.chmod(path, mode)


def run_shell(cmd: List[str], env: Dict[str, str]):
    # Run via bash -lc to allow expansions
    text = " ".join(shlex.quote(x) for x in cmd)
    subprocess.run(["bash", "-lc", text], check=True, env=env, cwd=str(REPO_ROOT))


def run_packages(args: List[str], env: Dict[str, str]):
    if not args:
        return
    op = args[0]
    names = args[1:]
    if op == "install" and names:
        run_shell(["sudo", "apt", "update"], env)
        run_shell(["sudo", "apt", "install", "-y", *names], env)
    elif op == "remove" and names:
        run_shell(["sudo", "apt", "remove", "-y", *names], env)


def run_service(args: List[str], env: Dict[str, str]):
    if len(args) < 2:
        return
    op, name = args[0], args[1]
    if op in {"start", "stop", "enable", "disable", "restart"}:
        run_shell(["sudo", "systemctl", op, name], env)


def run_copy(args: List[str], env: Dict[str, str]):
    # copy <local> <remote> [mode=0644] [user=...] [group=...]
    if len(args) < 2:
        return
    local = (REPO_ROOT / args[0]).resolve()
    remote = Path(args[1])
    mode = None
    user = None
    group = None
    for tok in args[2:]:
        if tok.startswith("mode="):
            mode = int(tok.split("=", 1)[1], 8)
        elif tok.startswith("user="):
            user = tok.split("=", 1)[1]
        elif tok.startswith("group="):
            group = tok.split("=", 1)[1]
    ensure_dir(remote.parent)
    # Use cp to preserve behavior
    run_shell(["cp", "-f", str(local), str(remote)], env)
    if mode is not None:
        os.chmod(remote, mode)
    if user or group:
        chown = f"{user or ''}:{group or ''}"
        run_shell(["sudo", "chown", chown, str(remote)], env)


def exec_task(task: Task, env: Dict[str, str]):
    for verb, args in task.actions:
        if verb == "shell":
            run_shell(args, env)
        elif verb == "packages":
            run_packages(args, env)
        elif verb == "service":
            run_service(args, env)
        elif verb == "directory":
            if not args:
                continue
            mode = "0755"
            kv = [a for a in args[1:] if a.startswith("mode=")]
            if kv:
                mode = kv[0].split("=", 1)[1]
            ensure_dir(Path(args[0]), mode)
        elif verb == "copy":
            run_copy(args, env)
        else:
            print(f"WARN: unknown verb '{verb}' in task {task.name}")


def main():
    tasks = load_tasks()
    if len(sys.argv) == 1 or sys.argv[1] in {"help", "--help", "-h"}:
        print("Usage: pf.py list | pf.py <task> [<task> ...]")
        sys.exit(0)
    if sys.argv[1] == "list":
        print("Available tasks:")
        for name in sorted(tasks.keys()):
            desc = tasks[name].desc
            print(f"  {name} - {desc}" if desc else f"  {name}")
        sys.exit(0)

    # Merge environment with venv PATH preference
    env = os.environ.copy()
    venv_bin = "/home/punk/.venv/bin"
    path = env.get("PATH", "")
    if venv_bin not in path:
        env["PATH"] = f"{venv_bin}:{path}"

    for tname in sys.argv[1:]:
        if tname not in tasks:
            print(f"ERROR: task '{tname}' not found. Run './pf.py list'", file=sys.stderr)
            sys.exit(2)
        print(f"==> {tname}")
        exec_task(tasks[tname], env)

if __name__ == "__main__":
    main()
