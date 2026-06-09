import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { FileTransferManager } from "../src/codex/fileTransferManager.js";

describe("FileTransferManager", () => {
  it("offers and downloads files inside configured workspaces", async () => {
    const root = await mkdtemp(path.join(os.tmpdir(), "codex-link-files-"));
    await mkdir(path.join(root, "lib"), { recursive: true });
    await writeFile(path.join(root, "lib", "note.txt"), "hello");

    const manager = new FileTransferManager({
      workspaces: [{ id: "default", label: "root", path: root }],
      maxBytes: 1024,
    });

    const offer = await manager.offerWorkspaceFile({
      sessionId: "s1",
      workspaceRoot: root,
      relativePath: "lib/note.txt",
      reason: "generated",
    });
    const download = await manager.download(offer.fileId);

    expect(offer.name).toBe("note.txt");
    expect(download.dataBase64).toBe(Buffer.from("hello").toString("base64"));
  });

  it("rejects path traversal outside workspace", async () => {
    const root = await mkdtemp(path.join(os.tmpdir(), "codex-link-files-"));
    const manager = new FileTransferManager({
      workspaces: [{ id: "default", label: "root", path: root }],
      maxBytes: 1024,
    });

    await expect(
      manager.offerWorkspaceFile({
        sessionId: "s1",
        workspaceRoot: root,
        relativePath: "../outside.txt",
        reason: "generated",
      }),
    ).rejects.toThrow(/outside workspace/);
  });

  it("rejects home directory paths before resolving them inside the workspace", async () => {
    const root = await mkdtemp(path.join(os.tmpdir(), "codex-link-files-"));
    const manager = new FileTransferManager({
      workspaces: [{ id: "default", label: "root", path: root }],
      maxBytes: 1024,
    });

    await expect(
      manager.offerWorkspaceFile({
        sessionId: "s1",
        workspaceRoot: root,
        relativePath: "~/.codex/src/cryptobot/validation.py",
        reason: "requested",
      }),
    ).rejects.toThrow(/workspace-relative path/);
  });

  it("reports missing workspace files without leaking raw realpath errors", async () => {
    const root = await mkdtemp(path.join(os.tmpdir(), "codex-link-files-"));
    const manager = new FileTransferManager({
      workspaces: [{ id: "default", label: "root", path: root }],
      maxBytes: 1024,
    });

    await expect(
      manager.offerWorkspaceFile({
        sessionId: "s1",
        workspaceRoot: root,
        relativePath: "src/cryptobot/validation.py",
        reason: "requested",
      }),
    ).rejects.toThrow(/File was not found in workspace: src\/cryptobot\/validation.py/);
  });

  it("rejects files above the configured size limit", async () => {
    const root = await mkdtemp(path.join(os.tmpdir(), "codex-link-files-"));
    await writeFile(path.join(root, "big.txt"), "too large");
    const manager = new FileTransferManager({
      workspaces: [{ id: "default", label: "root", path: root }],
      maxBytes: 4,
    });

    await expect(
      manager.offerWorkspaceFile({
        sessionId: "s1",
        workspaceRoot: root,
        relativePath: "big.txt",
        reason: "generated",
      }),
    ).rejects.toThrow(/too large/);
  });
});
