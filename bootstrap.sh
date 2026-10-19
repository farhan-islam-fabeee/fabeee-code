#!/usr/bin/env bash
# fabeee-code bootstrap: download (or update) the kit, then run its guided setup in the
# current folder.
#
#   cd your-project
#   curl -fsSL https://raw.githubusercontent.com/farhan-islam-fabeee/fabeee-code/main/bootstrap.sh | bash
#
# Setup options go after `bash -s --`, e.g. `... | bash -s -- --lang=ja --dry-run`.
#   FABEEE_CODE_HOME  where the kit is kept (default ~/.fabeee-code)
#   FABEEE_CODE_REF   branch or tag to use (default main)
#   FABEEE_CODE_REPO  git URL to clone (default this repo)
set -euo pipefail

# Everything runs inside main, so a partially downloaded script does nothing.
main() {
  local repo="${FABEEE_CODE_REPO:-https://github.com/farhan-islam-fabeee/fabeee-code.git}"
  local tarball="https://codeload.github.com/farhan-islam-fabeee/fabeee-code/tar.gz/${FABEEE_CODE_REF:-main}"
  local ref="${FABEEE_CODE_REF:-main}"
  local dir="${FABEEE_CODE_HOME:-$HOME/.fabeee-code}"
  local lang="${FABEEE_CODE_LANG:-}"
  if [[ -z $lang ]]; then
    case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in ja*) lang=ja ;; ko*) lang=ko ;; bn*) lang=bn ;; *) lang=en ;; esac
  fi

  msg() { # msg KEY ARG
    local en ja ko bn
    case $1 in
      clone)  en="Downloading fabeee-code to %s ..."; ja="fabeee-code を %s にダウンロードしています..."
              ko="fabeee-code를 %s에 내려받는 중..."; bn="fabeee-code %s-এ ডাউনলোড হচ্ছে ..." ;;
      update) en="Updating fabeee-code in %s ..."; ja="%s の fabeee-code を更新しています..."
              ko="%s의 fabeee-code를 업데이트하는 중..."; bn="%s-এ fabeee-code আপডেট হচ্ছে ..." ;;
      dirty)  en="%s has local changes; using it as is."; ja="%s にローカルの変更があるため、そのまま使います。"
              ko="%s에 로컬 변경 사항이 있어 그대로 사용합니다."; bn="%s-এ লোকাল পরিবর্তন আছে; যেমন আছে তেমনই ব্যবহার করা হচ্ছে।" ;;
      notkit) en="%s exists but isn't a fabeee-code folder. Set FABEEE_CODE_HOME to another path."
              ja="%s は存在しますが fabeee-code のフォルダーではありません。FABEEE_CODE_HOME で別の場所を指定してください。"
              ko="%s 폴더가 있지만 fabeee-code 폴더가 아닙니다. FABEEE_CODE_HOME으로 다른 경로를 지정하세요."
              bn="%s আছে, কিন্তু এটি fabeee-code ফোল্ডার নয়। FABEEE_CODE_HOME দিয়ে অন্য পথ দিন।" ;;
      tools)  en="Needs git, or curl and tar."; ja="git、または curl と tar が必要です。"
              ko="git 또는 curl과 tar가 필요합니다."; bn="git, অথবা curl ও tar প্রয়োজন।" ;;
      start)  en="Starting setup in %s"; ja="%s でセットアップを開始します"
              ko="%s에서 설정을 시작합니다"; bn="%s-এ সেটআপ শুরু হচ্ছে" ;;
    esac
    local fmt
    case $lang in ja) fmt=$ja ;; ko) fmt=$ko ;; bn) fmt=$bn ;; *) fmt=$en ;; esac
    printf -- "$fmt\n" "${2:-}"
  }
  die() { msg "$@" >&2; exit 1; }

  if [[ -e $dir && ! -f $dir/scripts/setup.sh ]]; then die notkit "$dir"; fi

  if git --version >/dev/null 2>&1; then
    if [[ -d $dir/.git ]]; then
      if [[ -n $(git -C "$dir" status --porcelain) ]]; then
        msg dirty "$dir"
      else
        msg update "$dir"
        git -C "$dir" fetch -q --depth 1 origin "$ref"
        git -C "$dir" checkout -q --detach FETCH_HEAD
      fi
    else
      [[ -e $dir ]] && rm -rf "$dir"   # an earlier tarball copy; checked above that it is the kit
      msg clone "$dir"
      git clone -q --depth 1 --branch "$ref" "$repo" "$dir"
    fi
  elif command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1; then
    local tmp
    tmp=$(mktemp -d)
    msg clone "$dir"
    curl -fsSL "$tarball" | tar -xz --strip-components=1 -C "$tmp"
    [[ -f $tmp/scripts/setup.sh ]] || { rm -rf "$tmp"; die notkit "$tarball"; }
    rm -rf "$dir"
    mkdir -p "$(dirname "$dir")"
    mv "$tmp" "$dir"
  else
    die tools
  fi

  msg start "$(pwd)"
  # Under `curl | bash`, stdin is the script itself, so give setup the terminal instead.
  if [[ -t 0 ]]; then
    exec bash "$dir/scripts/setup.sh" "$@"
  elif (exec </dev/tty) 2>/dev/null; then
    exec bash "$dir/scripts/setup.sh" "$@" </dev/tty
  else
    exec bash "$dir/scripts/setup.sh" "$@"
  fi
}

main "$@"
