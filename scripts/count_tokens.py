"""Compare token counts of skills/ (English) vs skills-ja/ (Japanese).

usage: python count_tokens.py <repo_root> <spec> [<spec> ...]

Each spec is LABEL=KIND:PATH, where KIND is
  hf       a Hugging Face tokenizer.json            (needs `tokenizers`)
  o200k    OpenAI's o200k_base.tiktoken file        (needs `tiktoken`)
  kimi     Moonshot's tiktoken.model (Kimi K2/K3)   (needs `tiktoken`)

example:
  python count_tokens.py . Qwen3.8=hf:~/.omlx/models/.../tokenizer.json GPT=o200k:o200k_base.tiktoken
"""
import glob
import os
import re
import sys

# Split pattern from OpenAI's tiktoken_ext/openai_public.py (o200k_base).
O200K_PAT = "|".join([
    r"""[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]*[\p{Ll}\p{Lm}\p{Lo}\p{M}]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?""",
    r"""[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]+[\p{Ll}\p{Lm}\p{Lo}\p{M}]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?""",
    r"""\p{N}{1,3}""",
    r""" ?[^\s\p{L}\p{N}]+[\r\n/]*""",
    r"""\s*[\r\n]+""",
    r"""\s+(?!\S)""",
    r"""\s+""",
])

# Split pattern from moonshotai/Kimi-K3 tokenization_kimi.py.
KIMI_PAT = "|".join([
    r"""[\p{Han}]+""",
    r"""[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}&&[^\p{Han}]]*[\p{Ll}\p{Lm}\p{Lo}\p{M}&&[^\p{Han}]]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?""",
    r"""[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}&&[^\p{Han}]]+[\p{Ll}\p{Lm}\p{Lo}\p{M}&&[^\p{Han}]]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?""",
    r"""\p{N}{1,3}""",
    r""" ?[^\s\p{L}\p{N}]+[\r\n]*""",
    r"""\s*[\r\n]+""",
    r"""\s+(?!\S)""",
    r"""\s+""",
])


def load(kind, path):
    path = os.path.expanduser(path)
    if kind == "hf":
        from tokenizers import Tokenizer
        tok = Tokenizer.from_file(path)
        return lambda t: len(tok.encode(t, add_special_tokens=False).ids)
    if kind in ("o200k", "kimi"):
        import tiktoken
        from tiktoken.load import load_tiktoken_bpe
        enc = tiktoken.Encoding(
            name=kind,
            pat_str=O200K_PAT if kind == "o200k" else KIMI_PAT,
            mergeable_ranks=load_tiktoken_bpe(path),
            special_tokens={},
        )
        return lambda t: len(enc.encode(t, disallowed_special=()))
    raise SystemExit(f"unknown tokenizer kind: {kind}")


def description(text):
    return re.search(r"^description: (.*)$", text, re.M).group(1)


def pct(a, b):
    return f"{(b - a) / a * 100:+.0f}%"


root = sys.argv[1]
pairs = []
for en_path in sorted(glob.glob(os.path.join(root, "skills", "*", "SKILL.md"))):
    name = os.path.basename(os.path.dirname(en_path))
    ja_path = os.path.join(root, "skills-ja", name, "SKILL.md")
    pairs.append((name, open(en_path).read(), open(ja_path).read()))

print(f"{'tokenizer':12} {'desc EN':>7} {'desc JA':>7} {'Δ':>5}   {'files EN':>8} {'files JA':>8} {'Δ':>5}   per-skill Δ (files)")
for spec in sys.argv[2:]:
    label, rest = spec.split("=", 1)
    kind, path = rest.split(":", 1)
    count = load(kind, path)
    d_en = sum(count(description(en)) for _, en, _ in pairs)
    d_ja = sum(count(description(ja)) for _, _, ja in pairs)
    f_en = sum(count(en) for _, en, _ in pairs)
    f_ja = sum(count(ja) for _, _, ja in pairs)
    per = [(count(ja) - count(en)) / count(en) * 100 for _, en, ja in pairs]
    print(f"{label:12} {d_en:7} {d_ja:7} {pct(d_en, d_ja):>5}   {f_en:8} {f_ja:8} {pct(f_en, f_ja):>5}   "
          f"{min(per):+.0f}% to {max(per):+.0f}%")

chars_en = sum(len(en) for _, en, _ in pairs)
chars_ja = sum(len(ja) for _, _, ja in pairs)
print(f"\ncharacters: EN {chars_en}  JA {chars_ja}  (pi's chars/4 estimate: EN {chars_en // 4}, JA {chars_ja // 4})")
