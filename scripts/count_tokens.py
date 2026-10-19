"""Compare token counts of English vs Japanese skill files.

usage: python count_tokens.py <tokenizer.json> <repo_root>
"""
import glob
import os
import re
import sys

from tokenizers import Tokenizer

tok = Tokenizer.from_file(sys.argv[1])
root = sys.argv[2]


def n(text):
    return len(tok.encode(text, add_special_tokens=False).ids)


def frontmatter(text):
    m = re.match(r"---\n(.*?)\n---\n", text, re.S)
    fm = m.group(1)
    name = re.search(r"^name: (.*)$", fm, re.M).group(1)
    desc = re.search(r"^description: (.*)$", fm, re.M).group(1)
    return name, desc


def prose_only(text):
    """Drop fenced code blocks and inline code, which are identical in both languages."""
    text = re.sub(r"```.*?```", "", text, flags=re.S)
    return re.sub(r"`[^`]*`", "", text)


rows = []
for en_path in sorted(glob.glob(os.path.join(root, "skills", "*", "SKILL.md"))):
    name = os.path.basename(os.path.dirname(en_path))
    ja_path = os.path.join(root, "skills-ja", name, "SKILL.md")
    en, ja = open(en_path).read(), open(ja_path).read()
    _, en_desc = frontmatter(en)
    _, ja_desc = frontmatter(ja)
    rows.append(dict(
        name=name,
        desc_en=n(en_desc), desc_ja=n(ja_desc),
        full_en=n(en), full_ja=n(ja),
        prose_en=n(prose_only(en)), prose_ja=n(prose_only(ja)),
        chars_en=len(en), chars_ja=len(ja),
        est_en=len(en) // 4, est_ja=len(ja) // 4,
    ))


def pct(a, b):
    return f"{(b - a) / a * 100:+.0f}%"


print(f"{'skill':16} {'desc EN':>7} {'desc JA':>7} {'Δ':>5}   {'file EN':>7} {'file JA':>7} {'Δ':>5}   {'prose EN':>8} {'prose JA':>8} {'Δ':>5}")
tot = {k: 0 for k in rows[0] if k != "name"}
for r in rows:
    for k in tot:
        tot[k] += r[k]
    print(f"{r['name']:16} {r['desc_en']:7} {r['desc_ja']:7} {pct(r['desc_en'], r['desc_ja']):>5}   "
          f"{r['full_en']:7} {r['full_ja']:7} {pct(r['full_en'], r['full_ja']):>5}   "
          f"{r['prose_en']:8} {r['prose_ja']:8} {pct(r['prose_en'], r['prose_ja']):>5}")
print(f"{'TOTAL':16} {tot['desc_en']:7} {tot['desc_ja']:7} {pct(tot['desc_en'], tot['desc_ja']):>5}   "
      f"{tot['full_en']:7} {tot['full_ja']:7} {pct(tot['full_en'], tot['full_ja']):>5}   "
      f"{tot['prose_en']:8} {tot['prose_ja']:8} {pct(tot['prose_en'], tot['prose_ja']):>5}")
print()
print(f"characters:            EN {tot['chars_en']}  JA {tot['chars_ja']}")
print(f"chars/token (prose):   EN {sum(len(prose_only(open(p).read())) for p in glob.glob(os.path.join(root, 'skills', '*', 'SKILL.md'))) / tot['prose_en']:.2f}"
      f"  JA {sum(len(prose_only(open(p).read())) for p in glob.glob(os.path.join(root, 'skills-ja', '*', 'SKILL.md'))) / tot['prose_ja']:.2f}")
print(f"pi chars/4 estimate:   EN {tot['est_en']} (actual {tot['full_en']})  JA {tot['est_ja']} (actual {tot['full_ja']})")
