"""python -m nexense ..."""
import argparse
import json
import sys
from pathlib import Path
from .controller import Controller, WorkflowError


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="python -m nexense", description="TEAM Nexense v4 sample workflow")
    p.add_argument("--repo", type=Path, default=Path.cwd(), help="Git repository root (default: cwd)")
    sub = p.add_subparsers(dest="command", required=True)
    def task(name: str):
        a = sub.add_parser(name)
        a.add_argument("id")
        return a
    a = task("start")
    a.add_argument("--mode", choices=["quick", "standard", "deep"], default="standard")
    for name in ("status", "submit-plan", "tickets-ready", "worktree", "resolve", "finish"):
        a = task(name)
        if name == "finish": a.add_argument("commit")
    a = task("review")
    a.add_argument("outcome", choices=["pass", "revise"])
    a = task("approve")
    a.add_argument("stage", choices=["plan", "tickets"])
    a = task("verify")
    a.add_argument("role", choices=["qa", "pm"])
    a.add_argument("outcome", choices=["pass", "fail"])
    a = task("dispatch")
    a.add_argument("role", choices=["pm", "qa", "implementer", "pro2"])
    a.add_argument("--dry-run", action="store_true")
    for name in ("send", "read", "prompt"):
        a = task(name)
        a.add_argument("role", choices=["pm", "qa", "implementer", "pro2"])
    return p


def main():
    args = parser().parse_args()
    try:
        c = Controller(args.repo)
        command = args.command.replace("-", "_")
        if command == "start": obj = c.start(args.id, args.mode)
        elif command == "status": obj = c.load(args.id)
        elif command == "submit_plan": obj = c.submit_plan(args.id)
        elif command == "review": obj = c.review(args.id, args.outcome)
        elif command == "approve": obj = c.approve(args.id, args.stage)
        elif command == "tickets_ready": obj = c.tickets_ready(args.id)
        elif command == "worktree": obj = c.create_worktree(args.id)
        elif command == "finish": obj = c.finish(args.id, args.commit)
        elif command == "verify": obj = c.verify(args.id, args.role, args.outcome)
        elif command == "resolve": obj = c.resolve(args.id)
        elif command == "dispatch": obj = c.dispatch(args.id, args.role, dry_run=args.dry_run)
        elif command == "send": obj = c.send(args.id, args.role)
        elif command == "read": obj = c.read(args.id, args.role)
        elif command == "prompt": obj = c.prompt(args.id, args.role)
        else: raise WorkflowError(f"Unrecognized: {command}")
        print(json.dumps(obj, ensure_ascii=False, indent=2) if isinstance(obj, dict) else obj)
    except WorkflowError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(2)

if __name__ == "__main__":
    main()
