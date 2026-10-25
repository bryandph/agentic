"""Unit fixtures for workspace-overrides: URL normalisation, lock walking,
URL and alias matching, and where `--` exec inserts the arguments.

Usage: python3 workspace-overrides-unit.py <dir containing workspace_overrides.py>
"""

import contextlib
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, sys.argv.pop(1))
import workspace_overrides as wo  # noqa: E402

SAME_REPO = [
    "git@forge.fixture.example:team/core.git",
    "forge.fixture.example:team/core",
    "ssh://git@forge.fixture.example/team/core.git",
    "ssh://git@forge.fixture.example:2222/team/core",
    "git+ssh://git@forge.fixture.example/team/core.git",
    "git+ssh://git@forge.fixture.example:2222/team/core.git",
    "https://forge.fixture.example/team/core",
    "https://forge.fixture.example/team/core.git",
    "HTTPS://Forge.Fixture.Example/team/core.git/",
    "git+https://forge.fixture.example/team/core.git",
    "git+https://forge.fixture.example/team/core?ref=main&rev=0123abcd",
    "http://forge.fixture.example/team/core.git#frag",
]
GITHUB = [
    "github:owner/repo",
    "github:owner/repo/some-branch",
    "github:owner/repo?ref=main",
    "https://github.com/owner/repo",
    "https://github.com/owner/repo.git",
    "git+https://github.com/owner/repo",
    "git@github.com:owner/repo.git",
    "ssh://git@github.com/owner/repo",
    "git+ssh://git@github.com/owner/repo.git",
]
NESTED_GROUP = [
    "gitlab:group%2Fsub/repo",
    "git@gitlab.com:group/sub/repo.git",
    "https://gitlab.com/group/sub/repo",
]
LOCAL = [
    "/srv/fixture/core.git",
    "/srv/fixture/core",
    "file:///srv/fixture/core.git",
    "git+file:///srv/fixture/core",
]
NO_REPOSITORY = ["", "path:./sub", "./sub", "sub", "nixpkgs", "flake:nixpkgs", "path:/srv/fixture/core", "tarball:https://x.fixture.example/a.tar.gz"]


class Normalise(unittest.TestCase):
    def assert_one(self, urls, expected):
        for url in urls:
            with self.subTest(url=url):
                self.assertEqual(wo.normalise(url), expected)

    def test_transports_and_spellings(self):
        self.assert_one(SAME_REPO, "forge.fixture.example/team/core")

    def test_github_shorthand(self):
        self.assert_one(GITHUB, "github.com/owner/repo")

    def test_nested_group(self):
        self.assert_one(NESTED_GROUP, "gitlab.com/group/sub/repo")

    def test_local(self):
        self.assert_one(LOCAL, "file:/srv/fixture/core")

    def test_no_repository(self):
        self.assert_one(NO_REPOSITORY, None)

    def test_same_name_different_remotes(self):
        a = wo.normalise("git@a.fixture.example:team/core.git")
        self.assertNotEqual(a, wo.normalise("git@b.fixture.example:team/core.git"))
        self.assertNotEqual(a, wo.normalise("https://a.fixture.example/other/core.git"))
        self.assertNotEqual(a, wo.normalise("https://a.fixture.example/core.git"))
        self.assertNotEqual(wo.normalise("github:owner/core"), wo.normalise("https://forge.fixture.example/owner/core"))

    def test_lock_attrs(self):
        self.assertEqual(wo.node_urls({"type": "github", "owner": "owner", "repo": "repo", "rev": "0"}), ["https://github.com/owner/repo"])
        self.assertEqual(wo.normalise(wo.node_urls({"type": "github", "owner": "o", "repo": "r", "host": "ghe.fixture.example"})[0]), "ghe.fixture.example/o/r")
        self.assertEqual(wo.normalise(wo.node_urls({"type": "gitlab", "owner": "group%2Fsub", "repo": "repo"})[0]), "gitlab.com/group/sub/repo")
        self.assertEqual(wo.node_urls({"type": "git", "url": "ssh://git@forge.fixture.example/team/core.git"}), ["ssh://git@forge.fixture.example/team/core.git"])
        self.assertEqual(wo.node_urls({"type": "path", "path": "./sub"}), [])
        self.assertEqual(wo.node_urls({"type": "indirect", "id": "nixpkgs"}), [])


LOCK = {
    "version": 7,
    "root": "root",
    "nodes": {
        "root": {"inputs": {"core": "core", "mirrored": "mirrored", "other": "other", "sub": "sub", "alias": ["core"], "gone": "gone"}},
        "core": {
            "locked": {"type": "git", "url": "ssh://git@forge.fixture.example/team/core.git", "rev": "0"},
            "original": {"type": "git", "url": "ssh://git@forge.fixture.example/team/core.git"},
            "inputs": {"dep": "dep", "pinned": ["other"]},
        },
        "dep": {"locked": {"type": "github", "owner": "owner", "repo": "dep"}, "original": {"type": "github", "owner": "owner", "repo": "dep"}},
        "mirrored": {"locked": {"type": "git", "url": "https://mirror.fixture.example/team/core.git"}, "original": {"type": "git", "url": "https://mirror.fixture.example/team/core.git"}},
        "other": {"locked": {"type": "git", "url": "https://elsewhere.fixture.example/team/core.git"}, "original": {"type": "git", "url": "https://elsewhere.fixture.example/team/core.git"}},
        "sub": {"locked": {"type": "path", "path": "./sub"}, "original": {"type": "path", "path": "./sub"}, "parent": []},
        "gone": {"locked": {"type": "git", "url": "https://forge.fixture.example/team/gone"}, "original": {"type": "git", "url": "https://forge.fixture.example/team/gone"}},
    },
}
MANIFEST = [
    {"key": "core", "url": "git@forge.fixture.example:team/core.git", "aliases": ["https://mirror.fixture.example/team/core.git"], "path": "core", "groups": ["nix"]},
    {"key": "dep", "url": "git@github.com:owner/dep.git", "aliases": [], "path": "dep", "groups": []},
    {"key": "gone", "url": "git@forge.fixture.example:team/gone.git", "aliases": [], "path": "gone", "groups": []},
    {"key": "subrepo", "url": "https://forge.fixture.example/team/sub.git", "aliases": [], "path": "subrepo", "groups": []},
]


class Matching(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        t = self.tmp.name
        self.root = os.path.join(t, "ws")
        for repo in ("core", "dep", "subrepo"):
            subprocess.run(["git", "init", "-q", os.path.join(self.root, repo)], check=True)
        self.flake = os.path.join(t, "consumer")
        os.makedirs(self.flake)
        with open(os.path.join(self.flake, "flake.lock"), "w") as f:
            json.dump(LOCK, f)
        self.manifest = os.path.join(t, "manifest.json")
        with open(self.manifest, "w") as f:
            json.dump(MANIFEST, f)
        os.environ.pop("WORKBENCH_WORKSPACE_OVERRIDES", None)

    def tearDown(self):
        self.tmp.cleanup()

    def run_main(self, *extra):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = wo.main(["--root", self.root, "--manifest", self.manifest, *extra, self.flake])
        self.assertEqual(code, 0)
        return out.getvalue(), err.getvalue()

    def overrides(self, stdout):
        import shlex

        args = shlex.split(stdout)
        self.assertEqual(args[-1], "--no-write-lock-file")
        self.assertEqual(args.count("--no-write-lock-file"), 1)
        return {args[i + 1]: args[i + 2] for i in range(0, len(args) - 1, 3) if args[i] == "--override-input"}

    def test_url_alias_nested_follows_missing(self):
        out, err = self.run_main()
        ov = self.overrides(out)
        ref = lambda key: f"git+file://{os.path.join(self.root, key)}"  # noqa: E731
        # Declared URL, mirror alias, and a nested github: input as `core/dep`.
        self.assertEqual(ov, {"core": ref("core"), "mirrored": ref("core"), "core/dep": ref("dep")})
        # Same repository name on another remote, follows, an unmapped
        # path input and a missing checkout get no override.
        self.assertNotIn("other", ov)
        self.assertNotIn("alias", ov)
        self.assertNotIn("core/pinned", ov)
        self.assertNotIn("sub", ov)
        self.assertIn("skip gone: matched gone", err)
        self.assertIn("does not exist", err)
        self.assertIn("alias follows core and picks up its override", err)
        for name in ("core", "mirrored", "core/dep"):
            self.assertIn(f"override {name} -> ", err)

    def test_map_checkout_only_scheme(self):
        wt = os.path.join(self.tmp.name, "core-wt")
        os.makedirs(wt)
        with open(os.path.join(self.root, "subrepo", ".gitmodules"), "w") as f:
            f.write("")
        out, _ = self.run_main("--map", "sub=subrepo", "--checkout", f"core={wt}", "--scheme", "path")
        ov = self.overrides(out)
        self.assertEqual(ov["sub"], f"path:{os.path.join(self.root, 'subrepo')}")
        self.assertEqual(ov["core"], f"path:{wt}")
        out, _ = self.run_main("--map", "sub=subrepo", "--only", "nix")
        self.assertEqual(set(self.overrides(out)), {"core", "mirrored"})
        out, _ = self.run_main("--map", "sub=subrepo", "--only", "subrepo")
        self.assertEqual(self.overrides(out), {"sub": f"git+file://{os.path.join(self.root, 'subrepo')}?submodules=1"})

    def test_declared_map_and_cli_precedence(self):
        path = os.path.join(self.tmp.name, "overrides.json")
        with open(path, "w") as f:
            json.dump({"sub": "subrepo", "other": "dep"}, f)
        os.environ["WORKBENCH_WORKSPACE_OVERRIDES"] = path
        out, err = self.run_main("--map", "other=core")
        ov = self.overrides(out)
        self.assertEqual(ov["sub"], f"git+file://{os.path.join(self.root, 'subrepo')}")
        self.assertEqual(ov["other"], f"git+file://{os.path.join(self.root, 'core')}")
        self.assertIn("mapped by declaration", err)
        self.assertIn("mapped by --map", err)

    def test_untracked_reminder(self):
        with open(os.path.join(self.root, "core", "new.nix"), "w") as f:
            f.write("{}")
        _, err = self.run_main()
        self.assertIn("git add -N", err)

    def test_usage_errors(self):
        for extra in (["--map", "sub=nope"], ["--only", "nope"], ["--map", "broken"]):
            with self.subTest(extra=extra), self.assertRaises(SystemExit) as e, contextlib.redirect_stderr(io.StringIO()):
                self.run_main(*extra)
            self.assertNotEqual(e.exception.code, 0)


class Exec(unittest.TestCase):
    def test_insertion(self):
        self.assertEqual(wo.insertion_point(["nix", "build", ".#x"]), 2)
        self.assertEqual(wo.insertion_point(["/nix/store/x/bin/nix", "eval", ".#x"]), 2)
        self.assertEqual(wo.insertion_point(["nix", "develop", "-c", "make"]), 2)
        self.assertEqual(wo.insertion_point(["nix", "flake", "check"]), 3)

    def test_refusals(self):
        for cmd in (["echo", "hi"], ["nix", "flake", "lock"], ["nix", "flake", "update"], ["nix", "-L", "build"], ["nix", "profile", "install"], ["nix"], []):
            with self.subTest(cmd=cmd), self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
                wo.insertion_point(cmd)


if __name__ == "__main__":
    unittest.main(verbosity=2)
