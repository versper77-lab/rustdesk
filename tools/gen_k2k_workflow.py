import re, sys
src = open(sys.argv[1], encoding="utf-8").read().split("\n")

def job_block(name):
    start = next(i for i, l in enumerate(src) if l == f"  {name}:")
    end = start + 1
    while end < len(src) and not re.match(r"^  [A-Za-z0-9_-]+:$", src[end]):
        end += 1
    return src[start:end]

def cut_steps_from(block, step_name):
    idx = next(i for i, l in enumerate(block) if l.strip() == f"- name: {step_name}")
    return block[:idx]

def drop_matrix_entries(block, keep_marker):
    out, buf, in_entry = [], [], False
    for l in block:
        if l.strip() == "- {":
            in_entry, buf = True, [l]
            continue
        if in_entry:
            buf.append(l)
            if l.strip() == "}":
                in_entry = False
                if any(keep_marker in b for b in buf):
                    out.extend(buf)
            continue
        out.append(l)
    return out

env_start = src.index("env:")
env_end = src.index("jobs:")
env = src[env_start:env_end]
env = [l for l in env if "inputs.publish-update-metadata" not in l]
env = [l.replace('"${{ inputs.upload-artifact }}"', '"true"') for l in env]
env = [l.replace('TAG_NAME: "${{ inputs.upload-tag }}"', 'TAG_NAME: "k2k"') for l in env]

bridge = job_block("generate-bridge")
topmost = drop_matrix_entries(job_block("build-RustDeskTempTopMostWindow"), "platform: x64")
win = drop_matrix_entries(job_block("build-for-windows-flutter"), "x86_64-pc-windows-msvc")
win = cut_steps_from(win, "Sign rustdesk files")
android = drop_matrix_entries(job_block("build-rustdesk-android"), "aarch64-linux-android")
android = cut_steps_from(android, "Setup sign tool version variable")

def fix(block):
    out = []
    for l in block:
        if l.strip() == "needs: [validate-update-metadata-keys]":
            continue
        l = l.replace("${{ inputs.upload-artifact }}", "true").replace("!inputs.upload-artifact", "false")
        out.append(l)
    while out and out[-1].strip() == "":
        out.pop()
    return out

win = [l.replace("name: rustdesk-unsigned-windows-${{ matrix.job.arch }}", "name: K2K-windows-${{ matrix.job.arch }}-portable") for l in fix(win)]
ios = fix(job_block("build-rustdesk-ios"))
ios = [l for l in ios if not l.lstrip().startswith("#")]
while ios and ios[-1].strip() == "":
    ios.pop()
ios += [
    "",
    "      - name: Package unsigned K2K ipa",
    "        shell: bash",
    "        run: |",
    "          cd flutter/build/ios/archive/Runner.xcarchive/Products/Applications",
    "          mkdir -p Payload",
    "          cp -R Runner.app Payload/",
    "          zip -qr \"$GITHUB_WORKSPACE/K2K-unsigned.ipa\" Payload",
    "",
    "      - name: Upload K2K ipa",
    "        uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1",
    "        with:",
    "          name: K2K-ios-unsigned-ipa",
    "          path: K2K-unsigned.ipa",
]
android = fix(android) + [
    "",
    "      - name: Upload K2K apk",
    "        uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1",
    "        with:",
    "          name: K2K-android-${{ matrix.job.arch }}-apk",
    "          path: signed-apk/*.apk",
]

header = [
    "# Generated from flutter-build.yml by tools/gen_k2k_workflow.py (K2K fork).",
    "# Builds only Windows x64 (portable folder) and Android arm64 (debug-signed apk)",
    "# and iOS (unsigned ipa for sideloading), uploaded as Actions artifacts. Signing and GitHub releases are skipped.",
    "name: K2K build",
    "",
    "on:",
    "  workflow_dispatch:",
    "  push:",
    "    branches:",
    "      - k2k",
    "",
    "concurrency:",
    "  group: k2k-build-${{ github.ref }}",
    "  cancel-in-progress: true",
    "",
]
out = header + env + ["jobs:"] + fix(bridge) + [""] + fix(topmost) + [""] + win + [""] + android + [""] + ios + [""]
open(sys.argv[2], "w", encoding="utf-8").write("\n".join(out))
