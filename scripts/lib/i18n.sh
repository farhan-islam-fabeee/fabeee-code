# Message catalogs shared by setup.sh and install.sh (bash 3.2 compatible).
# Catalogs live in lang/<code>.txt as key=text lines. The text is a printf format: use %s for
# arguments and %% for a literal percent sign. English loads first, so a key missing from a
# translation falls back to English.

I18N_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lang"
I18N_CODES="en ja ko bn"

load_catalog() {
  local file="$I18N_DIR/$1.txt" line
  [[ -f $file ]] || return 1
  while IFS= read -r line || [[ -n $line ]]; do
    [[ -z $line || $line == \#* ]] && continue
    printf -v "M_${line%%=*}" '%s' "${line#*=}"
  done < "$file"
}

valid_lang() { [[ " $I18N_CODES " == *" $1 "* ]]; }

set_lang() {
  local code=$1
  valid_lang "$code" || code=en
  load_catalog en
  [[ $code == en ]] || load_catalog "$code"
  FABEEE_CODE_LANG=$code
  export FABEEE_CODE_LANG
}

# t KEY [ARG...]: print the message for KEY, formatted with ARGs.
t() {
  local key="M_$1"
  shift
  local fmt="${!key:-$key}"
  printf -- "$fmt" "$@"
}

detect_lang() {
  case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in
    ja*) echo ja ;;
    ko*) echo ko ;;
    bn*) echo bn ;;
    *) echo en ;;
  esac
}

# choose_language: ask once, in all four languages, then load that catalog.
choose_language() {
  local codes=(en ja ko bn) def i=1 ans=""
  def=$(detect_lang)
  for c in "${codes[@]}"; do [[ $c == "$def" ]] && break; i=$((i + 1)); done
  printf '%s\n' "Choose a language / 言語を選んでください / 언어를 선택하세요 / ভাষা বেছে নিন"
  printf '  1) English\n  2) 日本語\n  3) 한국어\n  4) বাংলা\n'
  while true; do
    read -r -p "[1-4] (Enter = $i): " ans || exit 1
    ans=${ans:-$i}
    if [[ $ans =~ ^[1-4]$ ]]; then break; fi
    printf '%s\n' "1-4"
  done
  set_lang "${codes[$((ans - 1))]}"
}
