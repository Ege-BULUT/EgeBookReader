# Build <name>.tokenizer.json for a Marian model and prove a plain unigram Viterbi port matches MarianTokenizer.
# usage: python -I tokenizer.py <model_dir> <out.json> <prefix-or-none> <maxLength>
import json, sys, unicodedata
import numpy as np
import sentencepiece as spm
from sentencepiece import sentencepiece_model_pb2 as pb

# ---------------- the code to port to Dart (uses only the JSON) ----------------
def normalize(text, norm, max_key):
    """nmt_nfkc: greedy longest-match replacement table, then SentencePiece whitespace rules."""
    out = []; i = 0                                       # 1. at each code point take the longest key in norm
    while i < len(text):
        for L in range(min(max_key, len(text) - i), 0, -1):
            r = norm.get(text[i:i + L])
            if r is not None: out.append(r); i += L; break
        else: out.append(text[i]); i += 1                 # no rule: keep the code point
    out = ''.join(out)
    out = ' '.join(w for w in out.split(' ') if w)        # 2. trim, collapse runs of ' ' (only U+0020; step 1 maps others)
    return '▁' + out.replace(' ', '▁') if out else ''     # 3. dummy prefix + escape spaces

def viterbi(text, pieces, max_len, unk_score):
    """text: normalized string. pieces: dict piece->score (normal pieces only). Returns list of (piece, is_unk)."""
    f32 = np.float32                                      # SentencePiece sums in float32: Dart use a Float32List
    n = len(text)                                         # index by Unicode code point (Dart: use runes)
    best = [None] * (n + 1); best[0] = f32(0)
    back = [None] * (n + 1)                               # (start, piece, is_unk)
    for i in range(n):
        if best[i] is None: continue
        single = False
        for L in range(1, min(max_len, n - i) + 1):
            p = text[i:i + L]
            s = pieces.get(p)
            if s is None: continue
            if L == 1: single = True
            c = f32(best[i] + f32(s))                     # strict '>' : on ties the earlier start (longer piece) wins
            if best[i + L] is None or c > best[i + L]: best[i + L] = c; back[i + L] = (i, p, False)
        c = f32(best[i] + f32(unk_score))
        if not single and (best[i + 1] is None or c > best[i + 1]):   # char not in vocab: 1-char unknown node
            best[i + 1] = c; back[i + 1] = (i, text[i], True)
    out = []; j = n
    while j > 0:
        i, p, u = back[j]; out.append((p, u)); j = i
    out.reverse()
    merged = []                                           # consecutive unknown chars become one unknown token
    for p, u in out:
        if u and merged and merged[-1][1]: merged[-1] = (merged[-1][0] + p, True)
        else: merged.append((p, u))
    return merged

def encode(text, tok):
    pieces = {p: s for p, s, t in tok['_typed'] if t in (1, 4)}  # Dart: build from tok['source'] skipping specials
    ids = []
    if tok['prefix']: ids.append(tok['vocab'].index(tok['prefix']))
    for p, unk in viterbi(normalize(text, tok['normalize'], tok['_maxkey']), pieces, tok['_maxlen'], tok['unkScore']):
        ids.append(tok['_v2i'].get(p, tok['unk']))       # unknown surfaces too: vocab.json also holds target pieces
    return ids + [tok['eos']]

def decode(ids, tok):
    s = ''.join(tok['vocab'][i] for i in ids if i not in (tok['eos'], tok['pad']))
    return s.replace('▁', ' ').strip()

# ---------------- building the JSON ----------------
def charsmap_rules(blob):
    """Decode SentencePiece's precompiled_charsmap (uint32 trie size + Darts-clone double array + NUL-terminated
    replacement strings) into {source string: replacement}."""
    import struct
    n = struct.unpack('<I', blob[:4])[0]; units = struct.unpack(f'<{n // 4}I', blob[4:4 + n]); strs = blob[4 + n:]
    off = lambda u: (u >> 10) << ((u & (1 << 9)) >> 6)
    label = lambda u: u & ((1 << 31) | 0xFF)
    rules = {}
    def walk(pos, key):
        u = units[pos]
        if (u >> 8) & 1:                                  # has leaf: value sits at pos ^ offset
            v = units[pos ^ off(u)] & ((1 << 31) - 1); e = strs.index(b'\0', v)
            rules[key.decode('utf-8')] = strs[v:e].decode('utf-8')
        for c in range(1, 256):
            nxt = pos ^ off(u) ^ c
            if nxt < len(units) and label(units[nxt]) == c: walk(nxt, key + bytes([c]))
    walk(0, b'')
    return rules

def build(model_dir, prefix, max_length):
    m = pb.ModelProto(); m.ParseFromString(open(f'{model_dir}/source.spm', 'rb').read())
    sp = spm.SentencePieceProcessor(model_file=f'{model_dir}/source.spm')
    assert m.trainer_spec.model_type == 1 and m.normalizer_spec.name == 'nmt_nfkc' and not m.trainer_spec.byte_fallback
    full = charsmap_rules(m.normalizer_spec.precompiled_charsmap)
    # ponytail: keep single-code-point rules + kana voiced-mark compositions; Latin combining-mark and Hangul jamo
    # compositions (~220k rules, only hit by decomposed input that OCR never outputs) are dropped.
    norm = {k: v for k, v in full.items() if len(k) == 1 and k != v}
    norm.update({k: v for k, v in full.items() if len(k) > 1 and any(ord(c) in (0xFF9E, 0xFF9F, 0x3099, 0x309A) for c in k)
                 and ''.join(full.get(c, c) for c in k) != v})
    v2i = json.load(open(f'{model_dir}/vocab.json', encoding='utf-8'))
    V = max(v2i.values()) + 1; vocab = [None] * V
    for p, i in v2i.items(): vocab[i] = p
    cfg = json.load(open(f'{model_dir}/config.json'))
    normal = [p for p in m.pieces if p.type == 1]
    tok = {'source': [[p.piece, p.score] for p in m.pieces],
           'sourceTypes': [p.type for p in m.pieces],      # 1 normal, 2 unknown, 3 control; Viterbi uses type 1 only
           'vocab': vocab, 'eos': cfg['eos_token_id'], 'unk': v2i['<unk>'], 'pad': cfg['pad_token_id'],
           'start': cfg['decoder_start_token_id'], 'prefix': prefix, 'hidden': cfg['d_model'], 'maxLength': max_length,
           'unkScore': min(p.score for p in normal) - 10.0,  # SentencePiece kUnkPenalty = 10
           'normalize': norm}
    return tok, sp

def prepare(tok):
    tok['_typed'] = [(p, s, t) for (p, s), t in zip(tok['source'], tok['sourceTypes'])]
    tok['_maxlen'] = max(len(p) for p, s, t in tok['_typed'] if t == 1)
    tok['_maxkey'] = max(len(k) for k in tok['normalize'])
    tok['_v2i'] = {p: i for i, p in enumerate(tok['vocab']) if p is not None}
    return tok

TESTS = ["On average, interns work about 16 hours a day.", "MY MONTHLY SALARY IS AN ASTOUNDING... 459 DOLLARS!!!",
         "Not my daily salary. My monthly salary.", "That doesn't mean my hospital's treatment is bad.",
         "Pay a little more, but roughly 70% of interns at private university hospitals make under $1200 a month.",
         "...and the last touch.", "...mmm probably not strong enough.", "PLOP", "  leading   and trailing   spaces  ",
         "Tabs\tand\nnewlines", "Ｆｕｌｌｗｉｄｔｈ ＡＢＣ １２３！", "café naïve façade — “quotes” ‘single’ … ½ ﬁ",
         "Emoji 😀😀 and ☃ snowman", "İstanbul'da güzel bir gün, değil mi?", "おい、待て！", "どこへ行くんだ？",
         "話はまだ終わってない。", "明日は雨が降るでしょう。", "ｶﾀｶﾅ ﾃｽﾄ と ㈱ ㌔", "我爱你，世界", "x" * 3 + "​" + "zero width",
         "123-456 #hashtag @user", "ｶﾞｷﾞｸﾞ ﾊﾟﾋﾟ ｳﾞ", "が゙", ""]

if __name__ == '__main__':
    from transformers import MarianTokenizer
    model_dir, out, prefix, max_length = sys.argv[1], sys.argv[2], (None if sys.argv[3] == 'none' else sys.argv[3]), int(sys.argv[4])
    tok, sp = build(model_dir, prefix, max_length)
    json.dump(tok, open(out, 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))
    tok = prepare(json.load(open(out, encoding='utf-8')))
    ref = MarianTokenizer.from_pretrained(model_dir)
    bad = 0
    for t in TESTS:
        a = encode(t, tok); b = ref((prefix + ' ' if prefix else '') + t)['input_ids']
        ok = a == b; bad += not ok
        print('OK ' if ok else 'BAD', repr(t)[:60], a if not ok else '', b if not ok else '')
    print(f'{out}: {len(TESTS) - bad}/{len(TESTS)} match MarianTokenizer; normalize entries {len(tok["normalize"])}')
