#!/usr/bin/env node
/**
 * Заливает текущий код на build-сервер и поднимает публичный preview.
 *
 * Нужно в окружении:
 *   RAGDOLL_DEPLOY_HOST=138.201.50.89
 *   RAGDOLL_DEPLOY_PASS=...   (или вход по ключу без пароля)
 *
 * Usage: yarn deploy:preview
 */
import { spawnSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const HOST = process.env.RAGDOLL_DEPLOY_HOST ?? "138.201.50.89";
const USER = process.env.RAGDOLL_DEPLOY_USER ?? "root";
const REMOTE = `${USER}@${HOST}`;
const REMOTE_DIR = "/opt/ragdoll-faces";
const PORT = Number(process.env.RAGDOLL_DEPLOY_PORT ?? 8080);
// Порт должен быть открыт в ufw на сервере (`ufw allow 8080/tcp`).
const PASS = process.env.RAGDOLL_DEPLOY_PASS;

function run(cmd, args, opts = {}) {
  const env = { ...process.env };
  const usePass = Boolean(PASS);
  const wrap = usePass
    ? ["sshpass", "-e", cmd, ...args]
    : [cmd, ...args];
  if (usePass) env.SSHPASS = PASS;
  const res = spawnSync(wrap[0], wrap.slice(1), {
    cwd: ROOT,
    env,
    stdio: "inherit",
    ...opts,
  });
  if (res.status !== 0) {
    throw new Error(`${cmd} failed with exit ${res.status}`);
  }
}

const SSH_OPTS = [
  "-o",
  "StrictHostKeyChecking=accept-new",
  "-o",
  "PreferredAuthentications=password",
  "-o",
  "PubkeyAuthentication=no",
  "-o",
  "NumberOfPasswordPrompts=1",
];

function ssh(remoteCmd) {
  run("ssh", [...SSH_OPTS, REMOTE, remoteCmd]);
}

console.log(`\n→ sync → ${REMOTE}:${REMOTE_DIR}`);
run("rsync", [
  "-az",
  "--delete",
  "--exclude",
  "node_modules",
  "--exclude",
  "dist",
  "--exclude",
  "release",
  "--exclude",
  "test-artifacts",
  "--exclude",
  ".git",
  // 22 МБ wasm — сервер соберёт их сам из node_modules в yarn build.
  "--exclude",
  "public/mediapipe",
  // Secret-only files never leave the laptop; publishable Vite keys come via .env.local.
  "--exclude",
  ".env",
  "--exclude",
  ".env.production",
  "-e",
  `ssh ${SSH_OPTS.join(" ")}`,
  `${ROOT}/`,
  `${REMOTE}:${REMOTE_DIR}/`,
]);

console.log("→ yarn install + build");
// Vite вшивает VITE_* на этапе build — .env.local должен быть на сервере.
ssh(
  [
    `set -e`,
    `cd ${REMOTE_DIR}`,
    `test -f .env.local || { echo "MISSING .env.local (need VITE_SUPABASE_*)"; exit 1; }`,
    `grep -q '^VITE_SUPABASE_URL=' .env.local`,
    `grep -q '^VITE_SUPABASE_ANON_KEY=' .env.local`,
    `corepack enable`,
    `corepack prepare yarn@stable --activate`,
    `yarn install --immutable`,
    `yarn build`,
  ].join(" && "),
);

console.log("→ restart preview on :" + PORT);
// Нельзя `pkill -f serve` внутри той же ssh-команды — убьёт саму сессию.
// Отдельный ssh на старт: иначе nohup иногда держит канал открытым.
ssh(`fuser -k ${PORT}/tcp >/dev/null 2>&1 || true`);
ssh(
  `cd ${REMOTE_DIR} && (nohup npx --yes serve -s dist -l ${PORT} >/var/log/ragdoll-preview.log 2>&1 </dev/null & echo \$!); sleep 0.2`,
);
ssh(
  `for i in 1 2 3 4 5 6 7 8; do curl -sf -o /dev/null http://127.0.0.1:${PORT}/ && echo PREVIEW_OK && exit 0; sleep 0.5; done; echo PREVIEW_FAIL; exit 1`,
);

console.log(`\nОткрывай с телефона / любого устройства:\n  http://${HOST}:${PORT}/\n`);
