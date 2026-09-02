#!/usr/bin/env bash
# 灵想集（Bonnie 自媒体工作台）- 一键部署到 GitHub Pages
# 用法:
#   GITHUB_TOKEN=ghp_xxx bash deploy.sh "提交说明"
# 说明:
#   - 把 bonnie-studio.html 同步为 index.html（GitHub Pages 根路径入口）
#   - 先尝试 git push；若代理拦截 github.com，自动回退到 GitHub API 推送
#   - token 仅通过环境变量传入，绝不写入本文件或 .git/config
set -e

TOKEN="${GITHUB_TOKEN:?请先设置环境变量 GITHUB_TOKEN（如 export GITHUB_TOKEN=ghp_xxx）}"
MSG="${1:-更新 灵想集}"
REPO="1174641046-lab/writework"

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

# 1) 源文件同步到 Pages 入口
cp bonnie-studio.html index.html

# 2) 暂存
git add bonnie-studio.html index.html

# 3) 有改动才提交（保留本地历史）
CHANGED=0
if git diff --cached --quiet; then
  echo "没有需要提交的改动，仅同步远程。"
else
  git commit -m "$MSG"
  CHANGED=1
fi

# 4) 尝试 git push（代理正常时走这里）
if GIT_TERMINAL_PROMPT=0 git -c credential.helper= \
  -c "url.https://x-access-token:$TOKEN@github.com/.insteadOf=https://github.com/" \
  push origin main 2>/dev/null; then
  echo "部署完成（git push）-> https://1174641046-lab.github.io/writework/"
  exit 0
fi

echo "[warn] git push 被代理拦截，回退到 GitHub API 推送..."

# 仅在确有改动时走 API（无改动则跳过，避免误调接口）
if [ "$CHANGED" -ne 1 ]; then
  echo "无改动，跳过 API 推送。"
  exit 0
fi

# 5) GitHub API 兜底推送（api.github.com 可达）
b64="$(base64 -w0 < bonnie-studio.html)"
api_put() {
  local path="$1" sha
  sha="$(curl -s --max-time 20 -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPO/contents/$path" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{try{console.log(JSON.parse(d).sha)}catch(e){console.log('')}})")"
  curl -s --max-time 30 -X PUT -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" -H "Content-Type: application/json" \
    "https://api.github.com/repos/$REPO/contents/$path" \
    -d "$(node -e "console.log(JSON.stringify({message:process.argv[1],content:process.argv[2],sha:process.argv[3],branch:'main'}))" "$MSG" "$b64" "$sha")" \
    | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{try{console.log(JSON.parse(d).commit.sha)}catch(e){console.log('')}})"
}
RSHA1="$(api_put bonnie-studio.html)"
RSHA2="$(api_put index.html)"
echo "API 提交: bonnie-studio.html / index.html"

# 6) 回退本地 commit（代理无法 fetch 远程对象，本地历史与远程会自然分叉，
#    此处仅撤销本地 commit 保持工作区干净，不影响远程已部署内容）
if [ -n "$RSHA1" ]; then
  git reset --soft HEAD~1 2>/dev/null || true
  git reset -q 2>/dev/null || true
  echo "本地 commit 已回退，远程已更新 ($RSHA1)"
fi

echo "部署完成（API）-> https://1174641046-lab.github.io/writework/"
