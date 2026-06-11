import { execFile, spawn } from "node:child_process";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
const execFileAsync = promisify(execFile);
const DEFAULT_PACKAGE_NAME = "codex-link-host";
const MAX_OUTPUT_CHARS = 32 * 1024;
export class HostPackageUpdater {
    packageName;
    running = false;
    constructor(packageName = DEFAULT_PACKAGE_NAME) {
        this.packageName = packageName;
    }
    get isRunning() {
        return this.running;
    }
    async check() {
        const currentVersion = await readCurrentPackageVersion(this.packageName);
        try {
            const latestVersion = await readLatestPackageVersion(this.packageName);
            return {
                type: "host.update.status",
                packageName: this.packageName,
                currentVersion,
                latestVersion,
                updateAvailable: compareVersions(latestVersion, currentVersion) > 0,
                updateRunning: this.running,
            };
        }
        catch (error) {
            return {
                type: "host.update.status",
                packageName: this.packageName,
                currentVersion,
                updateAvailable: false,
                updateRunning: this.running,
                error: error instanceof Error ? error.message : String(error),
            };
        }
    }
    async run(onProgress) {
        if (this.running) {
            throw new Error("Host update is already running.");
        }
        this.running = true;
        try {
            onProgress({
                type: "host.update.progress",
                packageName: this.packageName,
                phase: "checking",
                line: `Checking ${this.packageName} on npm...`,
            });
            const status = await this.check();
            if (!status.latestVersion) {
                return {
                    type: "host.update.result",
                    packageName: this.packageName,
                    previousVersion: status.currentVersion,
                    updated: false,
                    exitCode: 1,
                    stdout: "",
                    stderr: status.error ?? "Could not read the latest npm package version.",
                    restartRequired: false,
                    message: "Host update check failed.",
                };
            }
            if (!status.updateAvailable) {
                onProgress({
                    type: "host.update.progress",
                    packageName: this.packageName,
                    phase: "completed",
                    line: `${this.packageName} is already up to date.`,
                });
                return {
                    type: "host.update.result",
                    packageName: this.packageName,
                    previousVersion: status.currentVersion,
                    latestVersion: status.latestVersion,
                    updated: false,
                    exitCode: 0,
                    stdout: "",
                    stderr: "",
                    restartRequired: false,
                    message: "Host package is already up to date.",
                };
            }
            onProgress({
                type: "host.update.progress",
                packageName: this.packageName,
                phase: "installing",
                line: `Installing ${this.packageName}@latest...`,
            });
            const result = await runNpmInstallLatest(this.packageName, onProgress);
            const success = result.exitCode === 0;
            onProgress({
                type: "host.update.progress",
                packageName: this.packageName,
                phase: success ? "completed" : "failed",
                line: success ? "Host package update completed." : "Host package update failed.",
            });
            return {
                type: "host.update.result",
                packageName: this.packageName,
                previousVersion: status.currentVersion,
                latestVersion: status.latestVersion,
                updated: success,
                exitCode: result.exitCode,
                stdout: truncate(result.stdout),
                stderr: truncate(result.stderr),
                restartRequired: success,
                message: success
                    ? "Host package updated. Restart the host bridge to use the new version."
                    : "Host package update failed.",
            };
        }
        finally {
            this.running = false;
        }
    }
}
async function readCurrentPackageVersion(packageName) {
    const start = path.dirname(fileURLToPath(import.meta.url));
    const packageJsonPath = await findPackageJson(start, packageName);
    const content = await readFile(packageJsonPath, "utf8");
    const record = JSON.parse(content);
    return typeof record.version === "string" && record.version.trim().length > 0
        ? record.version.trim()
        : "0.0.0";
}
async function findPackageJson(startDir, packageName) {
    let current = startDir;
    for (let index = 0; index < 8; index += 1) {
        const candidate = path.join(current, "package.json");
        try {
            const content = await readFile(candidate, "utf8");
            const record = JSON.parse(content);
            if (record.name === packageName) {
                return candidate;
            }
        }
        catch {
            // Keep walking upward.
        }
        const parent = path.dirname(current);
        if (parent === current)
            break;
        current = parent;
    }
    throw new Error(`Could not find package.json for ${packageName}.`);
}
async function readLatestPackageVersion(packageName) {
    const { stdout } = await execFileAsync(npmCommand(), ["view", packageName, "version", "--json"], {
        timeout: 20_000,
        maxBuffer: 256 * 1024,
    });
    const trimmed = stdout.trim();
    if (!trimmed) {
        throw new Error(`npm did not return a latest version for ${packageName}.`);
    }
    const parsed = JSON.parse(trimmed);
    if (typeof parsed === "string" && parsed.trim().length > 0) {
        return parsed.trim();
    }
    throw new Error(`npm returned an unreadable latest version for ${packageName}.`);
}
function runNpmInstallLatest(packageName, onProgress) {
    return new Promise((resolve) => {
        const child = spawn(npmCommand(), ["install", "-g", `${packageName}@latest`, "--no-audit", "--no-fund"], {
            stdio: ["ignore", "pipe", "pipe"],
            env: { ...process.env, npm_config_audit: "false", npm_config_fund: "false" },
        });
        let stdout = "";
        let stderr = "";
        child.stdout.on("data", (chunk) => {
            const text = chunk.toString("utf8");
            stdout = truncate(stdout + text);
            emitProgressLines(packageName, text, onProgress);
        });
        child.stderr.on("data", (chunk) => {
            const text = chunk.toString("utf8");
            stderr = truncate(stderr + text);
            emitProgressLines(packageName, text, onProgress);
        });
        child.on("error", (error) => {
            stderr = truncate(stderr + error.message);
            resolve({ exitCode: 1, stdout, stderr });
        });
        child.on("close", (code) => {
            resolve({ exitCode: typeof code === "number" ? code : 1, stdout, stderr });
        });
    });
}
function emitProgressLines(packageName, text, onProgress) {
    for (const line of text.split(/\r?\n/)) {
        const trimmed = line.trim();
        if (!trimmed)
            continue;
        onProgress({
            type: "host.update.progress",
            packageName,
            phase: "installing",
            line: trimmed.slice(0, 500),
        });
    }
}
function npmCommand() {
    return process.platform === "win32" ? "npm.cmd" : "npm";
}
function truncate(value) {
    return value.length <= MAX_OUTPUT_CHARS ? value : value.slice(value.length - MAX_OUTPUT_CHARS);
}
function compareVersions(left, right) {
    const leftParts = numericVersionParts(left);
    const rightParts = numericVersionParts(right);
    const length = Math.max(leftParts.length, rightParts.length);
    for (let index = 0; index < length; index += 1) {
        const delta = (leftParts[index] ?? 0) - (rightParts[index] ?? 0);
        if (delta !== 0)
            return delta;
    }
    return 0;
}
function numericVersionParts(version) {
    return version
        .replace(/^v/i, "")
        .split(/[.-]/)
        .map((part) => Number.parseInt(part, 10))
        .map((part) => (Number.isFinite(part) ? part : 0));
}
