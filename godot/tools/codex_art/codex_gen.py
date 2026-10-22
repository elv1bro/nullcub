#!/usr/bin/env python3
"""Пакетная генерация картинок через codex exec. jobs.json: [{"id", "prompt", "refs": [paths], "aspect": "portrait|landscape|square"}]
Запуск: python3 codex_gen.py jobs.json out_dir [parallel]"""
import json, os, subprocess, sys, shutil
from concurrent.futures import ThreadPoolExecutor

CODEX = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
STYLE = ("Art direction for the game NULL GRAVITY: physics ragdoll fighting game; fighters are modular toy-like robot puppets "
         "(segmented limbs on ball joints, round heads with screen faces or helmets, painted metal and plastic, bold colour blocks); "
         "fights happen in zero gravity inside a glowing translucent dome membrane called NULL, broadcast by the League like a TV show; "
         "mascot N0 is a small round white hovering drone-robot with rabbit-like ear antennae, a dark screen face with cyan eyes and a microphone. "
         "Look: stylized high-quality 3D render, cinematic lighting, deep navy and amber broadcast palette with cyan accents, clean readable shapes. "
         "Never write the words 'Ragdoll Master'.")


def run(job, out_dir):
    jid = job["id"]
    work = os.path.join(out_dir, "_work", jid)
    os.makedirs(work, exist_ok=True)
    target = os.path.join(out_dir, jid + ".png")
    if os.path.exists(target):
        return jid, "skip"
    refs = []
    for r in job.get("refs", []):
        dst = os.path.join(work, os.path.basename(r))
        shutil.copy(r, dst)
        refs += ["-i", dst]
    prompt = (f"Use your image generation tool to create exactly ONE image. Aspect: {job.get('aspect', 'landscape')}. "
              f"{STYLE}\n\nImage: {job['prompt']}\n\n"
              + ("The attached images are style/character references from the game — match their look. " if refs else "")
              + f"Save the generated PNG into the current directory as {jid}.png (copy it from wherever the tool stored it). "
              "Do not create any other files. Reply with just the path.")
    cmd = [CODEX, "exec", "--skip-git-repo-check", "-s", "workspace-write"] + refs + ["--", prompt]
    with open(os.path.join(work, "log.txt"), "w") as log:
        subprocess.run(["gtimeout", "900"] + cmd, cwd=work, stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT)
    produced = os.path.join(work, jid + ".png")
    if os.path.exists(produced):
        shutil.move(produced, target)
        return jid, "ok"
    return jid, "FAIL"


def main():
    jobs = json.load(open(sys.argv[1]))
    out_dir = sys.argv[2]
    par = int(sys.argv[3]) if len(sys.argv) > 3 else 3
    os.makedirs(out_dir, exist_ok=True)
    with ThreadPoolExecutor(par) as ex:
        for jid, st in ex.map(lambda j: run(j, out_dir), jobs):
            print(st, jid, flush=True)


if __name__ == "__main__":
    main()
