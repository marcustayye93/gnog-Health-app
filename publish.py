#!/usr/bin/env python3
"""Publish ~/workspace/gnog-schedules to GitHub Pages (repo: marcustayye93/gnog-Health-app).

Pushes the working tree via the git-database REST API (PAT can't use git transport
from this machine). Run any time the PWA changes.
"""
import base64
import json
import os
import sys
import urllib.request
import urllib.error

sys.path.insert(0, "/opt/hatch/skills/skill-creator/bin")
from dynamic_credentials import add_surrogate_to_request

API = "https://api.github.com"
OWNER = "marcustayye93"
REPO = "gnog-Health-app"
SRC = os.path.expanduser("~/workspace/gnog-schedules")


def api(method, path, payload=None):
    url = API + path
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Accept", "application/vnd.github+json")
    if data:
        req.add_header("Content-Type", "application/json")
    add_surrogate_to_request(req, "custom.github", allowed_hosts=("api.github.com",))
    with urllib.request.urlopen(req) as resp:
        body = resp.read()
        return json.loads(body) if body else {}


def blob_for(path):
    with open(path, "rb") as f:
        raw = f.read()
    return api("POST", f"/repos/{OWNER}/{REPO}/git/blobs",
               {"content": base64.b64encode(raw).decode(), "encoding": "base64"})["sha"]


def main():
    tree = []
    for root, dirs, files in os.walk(SRC):
        dirs[:] = [d for d in dirs if d != ".git"]
        for fn in sorted(files):
            full = os.path.join(root, fn)
            rel = os.path.relpath(full, SRC)
            sha = blob_for(full)
            tree.append({"path": rel, "mode": "100644", "type": "blob", "sha": sha})
    tree_sha = api("POST", f"/repos/{OWNER}/{REPO}/git/trees", {"tree": tree})["sha"]

    try:
        head = api("GET", f"/repos/{OWNER}/{REPO}/git/ref/heads/main")
        parents = [head["object"]["sha"]]
    except urllib.error.HTTPError as e:
        if e.code == 404:
            parents = []
        else:
            raise
    commit = api("POST", f"/repos/{OWNER}/{REPO}/git/commits",
                 {"message": "Gnog Schedules — PWA update",
                  "tree": tree_sha, "parents": parents})
    commit_sha = commit["sha"]
    print("commit", commit_sha)

    if parents:
        api("PATCH", f"/repos/{OWNER}/{REPO}/git/refs/heads/main", {"sha": commit_sha})
    else:
        api("POST", f"/repos/{OWNER}/{REPO}/git/refs",
            {"ref": "refs/heads/main", "sha": commit_sha})
    print("main ->", commit_sha[:8])


if __name__ == "__main__":
    main()
