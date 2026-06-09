import { randomUUID } from "node:crypto";
import { realpath, readFile, stat } from "node:fs/promises";
import path from "node:path";
import type { WorkspaceConfig } from "../config.js";
import type { FileDownloadMessage, FileOfferMessage } from "../protocol/messages.js";

export type FileTransferManagerOptions = {
  workspaces: WorkspaceConfig[];
  maxBytes: number;
};

export type OfferWorkspaceFileInput = {
  sessionId?: string;
  workspaceRoot: string;
  relativePath: string;
  reason: FileOfferMessage["reason"];
};

type StoredOffer = FileOfferMessage & {
  absolutePath: string;
};

export class FileTransferManager {
  private workspaces: WorkspaceConfig[];
  private readonly maxBytes: number;
  private readonly offers = new Map<string, StoredOffer>();

  constructor(options: FileTransferManagerOptions) {
    this.workspaces = options.workspaces;
    this.maxBytes = options.maxBytes;
  }

  setWorkspaces(workspaces: WorkspaceConfig[]): void {
    this.workspaces = workspaces;
  }

  async offerWorkspaceFile(input: OfferWorkspaceFileInput): Promise<FileOfferMessage> {
    const workspaceRoot = await this.resolveWorkspaceRoot(input.workspaceRoot);
    const relativePath = normalizeWorkspaceRelativePath(input.relativePath);
    const absolutePath = path.resolve(workspaceRoot, relativePath);
    if (!isInsideDirectory(absolutePath, workspaceRoot)) {
      throw new Error(`File is outside workspace: ${relativePath}`);
    }
    const resolvedFile = await realpath(absolutePath).catch((error: NodeJS.ErrnoException) => {
      if (error.code === "ENOENT") {
        throw new Error(`File was not found in workspace: ${relativePath}`);
      }
      throw error;
    });
    if (!isInsideDirectory(resolvedFile, workspaceRoot)) {
      throw new Error(`File is outside workspace: ${relativePath}`);
    }

    const stats = await stat(resolvedFile);
    if (!stats.isFile()) {
      throw new Error(`File is not downloadable: ${relativePath}`);
    }
    if (stats.size > this.maxBytes) {
      throw new Error(`File is too large to download: ${relativePath}`);
    }

    const fileId = randomUUID();
    const offer: StoredOffer = {
      type: "file.offer",
      fileId,
      sessionId: input.sessionId,
      path: path.relative(workspaceRoot, resolvedFile) || path.basename(resolvedFile),
      name: path.basename(resolvedFile),
      mimeType: mimeTypeFor(resolvedFile),
      sizeBytes: stats.size,
      reason: input.reason,
      absolutePath: resolvedFile,
    };
    this.offers.set(fileId, offer);
    return publicOffer(offer);
  }

  async download(fileId: string): Promise<FileDownloadMessage> {
    const offer = this.offers.get(fileId);
    if (!offer) {
      throw new Error(`Unknown file: ${fileId}`);
    }
    const stats = await stat(offer.absolutePath);
    if (!stats.isFile()) {
      throw new Error(`File is not downloadable: ${offer.path}`);
    }
    if (stats.size > this.maxBytes) {
      throw new Error(`File is too large to download: ${offer.path}`);
    }
    const bytes = await readFile(offer.absolutePath);
    return {
      type: "file.download",
      fileId,
      name: offer.name,
      mimeType: offer.mimeType,
      sizeBytes: bytes.byteLength,
      dataBase64: bytes.toString("base64"),
    };
  }

  private async resolveWorkspaceRoot(workspaceRoot: string): Promise<string> {
    const resolved = await realpath(path.resolve(workspaceRoot));
    const allowed = await Promise.all(
      this.workspaces.map(async (workspace) => realpath(path.resolve(workspace.path)).catch(() => path.resolve(workspace.path))),
    );
    if (!allowed.some((candidate) => candidate === resolved)) {
      throw new Error(`Unknown workspace root: ${workspaceRoot}`);
    }
    return resolved;
  }
}

function normalizeWorkspaceRelativePath(value: string): string {
  const normalized = value.trim().replace(/\\/g, "/").replace(/^@+/, "").trim();
  if (!normalized) {
    throw new Error("File must be a workspace-relative path.");
  }
  if (normalized === "~" || normalized.startsWith("~/") || normalized.startsWith("~\\")) {
    throw new Error(`File must be a workspace-relative path, not a home directory path: ${normalized}`);
  }
  if (path.isAbsolute(normalized) || /^[A-Za-z]:[\\/]/.test(normalized)) {
    throw new Error(`File must be a workspace-relative path, not an absolute path: ${normalized}`);
  }
  if (normalized.includes("\0")) {
    throw new Error("File path contains an invalid null byte.");
  }
  return normalized;
}

function publicOffer(offer: StoredOffer): FileOfferMessage {
  return {
    type: "file.offer",
    fileId: offer.fileId,
    sessionId: offer.sessionId,
    path: offer.path,
    name: offer.name,
    mimeType: offer.mimeType,
    sizeBytes: offer.sizeBytes,
    reason: offer.reason,
  };
}

function isInsideDirectory(candidate: string, root: string): boolean {
  const relative = path.relative(root, candidate);
  return relative.length === 0 || (!relative.startsWith("..") && !path.isAbsolute(relative));
}

export function mimeTypeFor(filePath: string): string | undefined {
  const ext = path.extname(filePath).toLowerCase();
  if (ext === ".txt" || ext === ".md" || ext === ".log") return "text/plain";
  if (ext === ".json") return "application/json";
  if (ext === ".png") return "image/png";
  if (ext === ".jpg" || ext === ".jpeg") return "image/jpeg";
  if (ext === ".webp") return "image/webp";
  if (ext === ".gif") return "image/gif";
  if (ext === ".dart" || ext === ".ts" || ext === ".js" || ext === ".tsx" || ext === ".jsx") return "text/plain";
  return undefined;
}
